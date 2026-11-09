import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:educa360/core/network/backend_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Headers;

String _b64(Object o) =>
    base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');

/// JWT de prueba (sin firma real): la librería solo lee `exp`/`iat`.
String _jwt(int expiresInSeconds, String tag) {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return '${_b64({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${_b64({'exp': now + expiresInSeconds, 'iat': now, 'tag': tag})}.sig';
}

Map<String, dynamic> _user() => {
      'id': '6c9aa9a0-5efa-400b-bdee-12998e35d3c3',
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': 'fixture@school.invalid',
      'app_metadata': {},
      'user_metadata': {},
      'created_at': '2026-10-19T00:00:00Z',
    };

/// Servidor de sesiones simulado: primer login con [firstExpiresIn]; cada
/// renovación entrega un token de 1 h salvo que [refreshBehavior] diga otra cosa.
class _Auth {
  _Auth({required this.firstExpiresIn});
  final int firstExpiresIn;
  int refreshes = 0;
  http.Response Function(http.Request)? refreshBehavior;

  MockClient get client => MockClient((request) async {
        final grant = request.url.queryParameters['grant_type'];
        if (grant == 'refresh_token') {
          refreshes++;
          final custom = refreshBehavior?.call(request);
          if (custom != null) return custom;
          return _json({
            'access_token': _jwt(3600, 'renovado-$refreshes'),
            'token_type': 'bearer',
            'refresh_token': 'refresh-$refreshes',
            'expires_in': 3600,
            'user': _user(),
          });
        }
        return _json({
          'access_token': _jwt(firstExpiresIn, 'inicial'),
          'token_type': 'bearer',
          'refresh_token': 'refresh-0',
          'expires_in': firstExpiresIn,
          'user': _user(),
        });
      });

  http.Response _json(Object body, [int status = 200]) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );
}

/// Adaptador HTTP del backend con respuestas en cola; registra el token usado.
class _Backend implements HttpClientAdapter {
  _Backend(this.queue);
  final List<ResponseBody Function()> queue;
  final tokens = <String>[];

  static ResponseBody ok(Object data) => ResponseBody.fromString(
        jsonEncode({'ok': true, 'data': data}),
        200,
        headers: {
          'content-type': ['application/json'],
        },
      );

  static ResponseBody unauthorized([String code = 'unauthorized']) =>
      ResponseBody.fromString(
        jsonEncode({
          'ok': false,
          'error': {'code': code, 'message': 'Sesión inválida o expirada.'},
        }),
        401,
        headers: {
          'content-type': ['application/json'],
        },
      );

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    tokens
        .add('${options.headers['Authorization']}'.replaceFirst('Bearer ', ''));
    return queue.removeAt(0)();
  }

  @override
  void close({bool force = false}) {}
}

String _tag(String jwt) => (jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(jwt.split('.')[1]))),)
    as Map)['tag'] as String;

Future<(SupabaseClient, BackendApiClient, _Backend, _Auth)> _setUp({
  required int firstExpiresIn,
  required List<ResponseBody Function()> responses,
}) async {
  final auth = _Auth(firstExpiresIn: firstExpiresIn);
  final supabase = SupabaseClient(
    'https://fixture.supabase.co',
    'public-fixture',
    httpClient: auth.client,
  );
  await supabase.auth.signInWithPassword(
    email: 'fixture@school.invalid',
    password: 'fixture',
  );
  final backend = _Backend(responses);
  final dio = Dio()..httpClientAdapter = backend;
  return (
    supabase,
    BackendApiClient(supabase: supabase, dio: dio),
    backend,
    auth
  );
}

void main() {
  test('renueva por adelantado un token que vence en menos de 60 s', () async {
    final (supabase, api, backend, auth) = await _setUp(
      firstExpiresIn: 30,
      responses: [
        () => _Backend.ok({'v': 1}),
      ],
    );
    addTearDown(() async {
      api.dispose();
      await supabase.dispose();
    });

    expect(await api.get('/algo'), {'v': 1});
    expect(auth.refreshes, 1);
    expect(_tag(backend.tokens.single), 'renovado-1',
        reason: 'usa el token nuevo',);
  });

  test('con el token vigente no renueva', () async {
    final (supabase, api, backend, auth) = await _setUp(
      firstExpiresIn: 3600,
      responses: [
        () => _Backend.ok({'v': 1}),
      ],
    );
    addTearDown(() async {
      api.dispose();
      await supabase.dispose();
    });

    await api.get('/algo');
    expect(auth.refreshes, 0);
    expect(_tag(backend.tokens.single), 'inicial');
  });

  test(
      'ante un 401 unauthorized renueva una vez y reintenta con el token nuevo',
      () async {
    final (supabase, api, backend, auth) = await _setUp(
      firstExpiresIn: 3600,
      responses: [
        () => _Backend.unauthorized(),
        () => _Backend.ok({'v': 2}),
      ],
    );
    addTearDown(() async {
      api.dispose();
      await supabase.dispose();
    });

    expect(await api.get('/algo'), {'v': 2});
    expect(auth.refreshes, 1);
    expect(backend.tokens.map(_tag), ['inicial', 'renovado-1']);
  });

  test(
      'una escritura que recibe 401 también se reintenta (el 401 no ejecutó nada)',
      () async {
    final (supabase, api, backend, auth) = await _setUp(
      firstExpiresIn: 3600,
      responses: [
        () => _Backend.unauthorized(),
        () => _Backend.ok({'creado': true}),
      ],
    );
    addTearDown(() async {
      api.dispose();
      await supabase.dispose();
    });

    expect(await api.post('/assignments/upsert', data: {'a': 1}),
        {'creado': true},);
    expect(backend.tokens.length, 2);
    expect(auth.refreshes, 1);
  });

  test('varias solicitudes con 401 a la vez comparten UNA sola renovación',
      () async {
    final (supabase, api, backend, auth) = await _setUp(
      firstExpiresIn: 3600,
      responses: [
        () => _Backend.unauthorized(),
        () => _Backend.unauthorized(),
        () => _Backend.unauthorized(),
        () => _Backend.ok({'n': 1}),
        () => _Backend.ok({'n': 2}),
        () => _Backend.ok({'n': 3}),
      ],
    );
    addTearDown(() async {
      api.dispose();
      await supabase.dispose();
    });

    final results = await Future.wait([
      api.get('/a'),
      api.get('/b'),
      api.get('/c'),
    ]);
    expect(results.length, 3);
    expect(auth.refreshes, 1, reason: 'un solo refresh token en vuelo');
    expect(backend.tokens.length, 6);
  });

  test(
      'si la renovación falla (refresh token revocado) cierra la sesión local y propaga el 401',
      () async {
    final (supabase, api, _, auth) = await _setUp(
      firstExpiresIn: 3600,
      responses: [() => _Backend.unauthorized()],
    );
    auth.refreshBehavior = (_) => http.Response(
          jsonEncode({
            'error': 'invalid_grant',
            'error_description':
                'Invalid Refresh Token: Refresh Token Not Found',
          }),
          400,
          headers: {'content-type': 'application/json'},
        );
    final events = <AuthChangeEvent>[];
    final sub =
        supabase.auth.onAuthStateChange.listen((e) => events.add(e.event));
    addTearDown(() async {
      await sub.cancel();
      api.dispose();
      await supabase.dispose();
    });

    await expectLater(
      api.get('/algo'),
      throwsA(
        isA<BackendApiException>().having((e) => e.statusCode, 'status', 401),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(supabase.auth.currentSession, isNull);
    expect(events, contains(AuthChangeEvent.signedOut));
  });

  test('un 401 que no es de sesión (otro código) no se reintenta', () async {
    final (supabase, api, backend, auth) = await _setUp(
      firstExpiresIn: 3600,
      responses: [() => _Backend.unauthorized('two_factor_expired')],
    );
    addTearDown(() async {
      api.dispose();
      await supabase.dispose();
    });

    await expectLater(api.get('/algo'), throwsA(isA<BackendApiException>()));
    expect(auth.refreshes, 0);
    expect(backend.tokens.length, 1);
  });

  test('sin red al renovar no cierra la sesión', () async {
    final (supabase, api, _, auth) = await _setUp(
      firstExpiresIn: 3600,
      responses: [() => _Backend.unauthorized()],
    );
    auth.refreshBehavior = (r) => throw http.ClientException('sin red', r.url);
    addTearDown(() async {
      api.dispose();
      await supabase.dispose();
    });

    await expectLater(api.get('/algo'), throwsA(isA<BackendApiException>()));
    expect(supabase.auth.currentSession, isNotNull,
        reason: 'un fallo de red no es el fin de la sesión',);
  });
}
