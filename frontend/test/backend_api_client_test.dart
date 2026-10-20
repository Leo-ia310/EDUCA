import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:dio/dio.dart';
import 'package:educa360/core/network/backend_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Headers;

class _Adapter implements HttpClientAdapter {
  final started = Completer<RequestOptions>();
  final response = Completer<ResponseBody>();
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture,) {
    if (!started.isCompleted) started.complete(options);
    cancelFuture?.then((_) {
      if (!response.isCompleted) {
        response.completeError(DioException(
            requestOptions: options, type: DioExceptionType.cancel,),);
      }
    });
    return response.future;
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Dio dio;
  late SupabaseClient supabase;
  late BackendApiClient api;

  setUp(() {
    dio = Dio();
    supabase = SupabaseClient('https://fixture.supabase.co', 'public-fixture');
    api = BackendApiClient(supabase: supabase, dio: dio);
  });
  tearDown(() async {
    api.dispose();
    await supabase.dispose();
  });

  for (final type in [
    DioExceptionType.connectionError,
    DioExceptionType.connectionTimeout,
    DioExceptionType.unknown,
  ]) {
    test('login network failure $type has no raw browser diagnostics',
        () async {
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.reject(
            DioException(
              requestOptions: options,
              type: type,
              message:
                  'XMLHttpRequest onError callback CORS internal diagnostic',
            ),
          ),
        ),
      );
      await expectLater(
        api.post('/auth/login', authenticated: false),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'safe Spanish message',
            allOf(
              startsWith(
                type == DioExceptionType.connectionTimeout
                    ? 'El servidor'
                    : 'No se pudo',
              ),
              isNot(contains('XMLHttpRequest')),
              isNot(contains('CORS')),
            ),
          ),
        ),
      );
    });
  }

  test('login preserves the controlled invalid credentials response', () async {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.reject(
          DioException(
            requestOptions: options,
            type: DioExceptionType.badResponse,
            response: Response<dynamic>(
              requestOptions: options,
              statusCode: 401,
              data: {
                'ok': false,
                'error': {'message': 'Credenciales incorrectas.'},
              },
            ),
          ),
        ),
      ),
    );
    await expectLater(
      api.post('/auth/login', authenticated: false),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'server message',
          'Credenciales incorrectas.',
        ),
      ),
    );
  });
  test('429 preserves retry-after and correlation ID without automatic retries',
      () async {
    var calls = 0;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          calls++;
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.badResponse,
              response: Response<dynamic>(
                requestOptions: options,
                statusCode: 429,
                headers: Headers.fromMap({
                  'retry-after': ['12'],
                  'x-request-id': ['request-42'],
                }),
                data: {
                  'ok': false,
                  'error': {'code': 'rate_limited', 'message': 'Espera.'},
                },
              ),
            ),
          );
        },
      ),
    );
    await expectLater(
      api.post('/auth/login', authenticated: false),
      throwsA(
        isA<BackendApiException>()
            .having((e) => e.retryable, 'retryable', true)
            .having((e) => e.statusCode, 'status', 429)
            .having((e) => e.retryAfter, 'retry', const Duration(seconds: 12))
            .having((e) => e.requestId, 'request', 'request-42'),
      ),
    );
    expect(calls, 1);
  });
  test('dispose cancels a transport request and future requests stay cancelled',
      () async {
    final adapter = _Adapter();
    dio.httpClientAdapter = adapter;
    final pending = api.post('/auth/login', authenticated: false);
    final options = await adapter.started.future;
    expect(options.connectTimeout, const Duration(seconds: 15));
    expect(options.receiveTimeout, const Duration(seconds: 75));
    final failed = expectLater(
        pending,
        throwsA(isA<BackendApiException>()
            .having((e) => e.code, 'code', 'request_cancelled')
            .having((e) => e.retryable, 'retryable', false),),);
    api.dispose();
    await failed;
    await expectLater(
        api.get('/anything', authenticated: false),
        throwsA(isA<BackendApiException>()
            .having((e) => e.code, 'code', 'request_cancelled'),),);
  });
  test('sign out cancels requests for the previous account', () async {
    api.dispose();
    await supabase.dispose();
    final client = MockClient(
      (request) async => http.Response(
        jsonEncode(
          request.url.path.endsWith('/token')
              ? {
                  'access_token': 'fixture-token',
                  'token_type': 'bearer',
                  'refresh_token': 'fixture-refresh',
                  'expires_in': 3600,
                  'user': {
                    'id': '6c9aa9a0-5efa-400b-bdee-12998e35d3c3',
                    'aud': 'authenticated',
                    'role': 'authenticated',
                    'email': 'fixture@school.invalid',
                    'app_metadata': {},
                    'user_metadata': {},
                    'created_at': '2026-10-19T00:00:00Z',
                  },
                }
              : {},
        ),
        200,
        headers: {'content-type': 'application/json'},
        request: request,
      ),
    );
    supabase = SupabaseClient('https://fixture.supabase.co', 'public-fixture',
        httpClient: client,);
    await supabase.auth.signInWithPassword(
        email: 'fixture@school.invalid', password: 'fixture',);
    dio = Dio();
    final adapter = _Adapter();
    dio.httpClientAdapter = adapter;
    api = BackendApiClient(supabase: supabase, dio: dio);
    final pending = api.get('/chats/conversations');
    await adapter.started.future;
    final failed = expectLater(
        pending,
        throwsA(isA<BackendApiException>()
            .having((e) => e.code, 'code', 'request_cancelled'),),);
    await supabase.auth.signOut();
    await failed;
    client.close();
  });
}
