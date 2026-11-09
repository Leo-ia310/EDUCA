import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:educa360/core/network/backend_api_client.dart';
import 'package:educa360/features/attendance/data/datasources/attendance_remote_datasource.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Headers;

String _b64(Object o) =>
    base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');

String _jwt() {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return '${_b64({'alg': 'HS256'})}.${_b64({'exp': now + 3600, 'iat': now})}.s';
}

/// Backend simulado: responde por ruta.
class _Routes implements HttpClientAdapter {
  _Routes({required this.classes, required this.schedules});
  final List<Map<String, dynamic>> classes;
  final Object? schedules; // lista de bloques, o `null` para simular un fallo

  ResponseBody _ok(Object data) => ResponseBody.fromString(
        jsonEncode({'ok': true, 'data': data}),
        200,
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
    if (options.path.endsWith('/business-api')) return _ok(classes);
    if (options.path.endsWith('/schedules/mine')) {
      if (schedules == null) {
        return ResponseBody.fromString(
          jsonEncode({
            'ok': false,
            'error': {'code': 'boom', 'message': 'fallo'},
          }),
          500,
          headers: {
            'content-type': ['application/json'],
          },
        );
      }
      return _ok({'schedules': schedules});
    }
    throw StateError('ruta inesperada: ${options.path}');
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _class(int id, String subject) => {
      'classId': id,
      'groupId': 1,
      'subjectName': subject,
      'groupName': '1er Grado',
      'startTime': '',
      'endTime': '',
      'studentCount': 10,
      'isOwner': true,
      'permissions': ['attendance.write'],
    };

Map<String, dynamic> _slot(int classId, String start, String end,
        {int? weekdayIndex, String kind = 'class', String? room = 'Aula 1',}) =>
    {
      'kind': kind,
      'classId': '$classId',
      'weekdayIndex': weekdayIndex ?? DateTime.now().weekday - 1,
      'startTime': start,
      'endTime': end,
      'room': room,
    };

Future<AttendanceRemoteDataSource> _remote(_Routes routes) async {
  final auth = MockClient(
    (request) async => http.Response(
      jsonEncode({
        'access_token': _jwt(),
        'token_type': 'bearer',
        'refresh_token': 'r',
        'expires_in': 3600,
        'user': {
          'id': '6c9aa9a0-5efa-400b-bdee-12998e35d3c3',
          'aud': 'authenticated',
          'role': 'authenticated',
          'email': 'f@s.invalid',
          'app_metadata': {},
          'user_metadata': {},
          'created_at': '2026-10-19T00:00:00Z',
        },
      }),
      200,
      headers: {'content-type': 'application/json'},
    ),
  );
  final supabase =
      SupabaseClient('https://fixture.supabase.co', 'k', httpClient: auth);
  await supabase.auth.signInWithPassword(email: 'f@s.invalid', password: 'x');
  final api = BackendApiClient(
    supabase: supabase,
    dio: Dio()..httpClientAdapter = routes,
  );
  addTearDown(() async {
    api.dispose();
    await supabase.dispose();
  });
  return AttendanceRemoteDataSource(api);
}

void main() {
  test('completa hora y aula con el horario de hoy y pone primero lo de hoy',
      () async {
    final remote = await _remote(
      _Routes(
        classes: [
          _class(1, 'Matemáticas'),
          _class(2, 'Lengua'),
          _class(3, 'Física'),
        ],
        schedules: [
          _slot(2, '10:00', '11:00'),
          _slot(2, '08:00', '09:00', room: 'Aula 7'), // el más temprano gana
          _slot(3, '07:30', '08:30'),
          _slot(1, '09:00', '10:00', weekdayIndex: (DateTime.now().weekday) % 7),
          _slot(1, '09:00', '10:00', kind: 'break'), // un receso no es una clase
        ],
      ),
    );

    final list = await remote.todaysClasses(teacherId: 0);

    expect(list.map((c) => c.subjectName), ['Física', 'Lengua', 'Matemáticas']);
    final fisica = list[0];
    expect(fisica.scheduledToday, isTrue);
    expect((fisica.startTime, fisica.endTime), ('07:30', '08:30'));
    final lengua = list[1];
    expect((lengua.startTime, lengua.endTime, lengua.classroom),
        ('08:00', '09:00', 'Aula 7'),);
    final mate = list[2];
    expect(mate.scheduledToday, isFalse, reason: 'hoy no le toca');
    expect(mate.startTime, isEmpty);
  });

  test('si el horario falla, devuelve todas las clases sin bloquear el pase',
      () async {
    final remote = await _remote(
      _Routes(
        classes: [_class(1, 'Matemáticas'), _class(2, 'Lengua')],
        schedules: null,
      ),
    );

    final list = await remote.todaysClasses(teacherId: 0);

    expect(list.length, 2);
    expect(list.every((c) => c.scheduledToday), isTrue);
  });
}
