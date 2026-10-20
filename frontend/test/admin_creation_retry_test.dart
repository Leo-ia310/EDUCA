import 'dart:convert';
import 'package:educa360/core/network/backend_api_client.dart';
import 'package:educa360/features/admin/data/admin_backend_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class Api implements BackendApiClient {
  BackendApiException? failure = BackendApiException('Respuesta perdida',
      statusCode: 503, code: 'provisioning_pending', retryable: true,);
  final requests = <Map<String, dynamic>>[];
  @override
  Future<dynamic> post(String path,
      {Map<String, dynamic>? data,
      Map<String, dynamic>? queryParameters,
      bool authenticated = true,}) async {
    requests
        .add(Map<String, dynamic>.from(jsonDecode(jsonEncode(data)) as Map));
    if (failure != null) throw failure!;
    return {
      'student': {'id': '1'},
      'teacher': {'id': '2'},
    };
  }

  @override
  Future<dynamic> patch(String path,
      {Map<String, dynamic>? data,
      Map<String, dynamic>? queryParameters,
      bool authenticated = true,}) async {
    requests.add(Map<String, dynamic>.from(data!));
    return {
      'student': {'id': '1'},
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final payload = {
    'firstName': 'Fixture',
    'lastName': 'Test',
    'email': 'fixture@school.invalid',
    'password': 'fixture-password',
  };
  test(
      'creation key and generated code survive repository recreation; preferences never contain the password',
      () async {
    final api = Api(),
        first = AdminBackendRepository(Api(), creationScope: '1:actor');
    await expectLater(first.createPeople('students', payload),
        throwsA(isA<BackendApiException>()),);
    first.dispose();
    final reopened = AdminBackendRepository(api, creationScope: '1:actor');
    await expectLater(reopened.createPeople('students', payload),
        throwsA(isA<BackendApiException>()),);
    final request = api.requests.single;
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().length, 1);
    final stored = prefs.getString(prefs.getKeys().single)!;
    expect(request['requestId'], stored);
    expect(request['studentCode'], 'EST-$stored');
    expect(stored, hasLength(36));
    expect(prefs.getKeys().any((key) => key.contains(payload['password']!)),
        isFalse,);
    api.failure = null;
    await reopened.createPeople('students', payload);
    expect(api.requests[0], api.requests[1]);
    expect(prefs.getKeys(), isEmpty);
  });
  test(
      'pending requests are isolated by account and cannot be overwritten with another key',
      () async {
    final api = Api(),
        a = AdminBackendRepository(api, creationScope: '1:a'),
        b = AdminBackendRepository(api, creationScope: '1:b');
    await expectLater(a.createPeople('students', payload),
        throwsA(isA<BackendApiException>()),);
    await expectLater(b.createPeople('students', payload),
        throwsA(isA<BackendApiException>()),);
    expect(api.requests[0]['requestId'], isNot(api.requests[1]['requestId']));
    await expectLater(
        a.createPeople(
            'students', {...payload, 'requestId': const Uuid().v4()},),
        throwsStateError,);
    expect(api.requests.length, 2);
  });
  test(
      'only an explicit Auth rejection retires a key; editing an existing person adds no creation fields',
      () async {
    final api = Api(),
        repo = AdminBackendRepository(api, creationScope: '1:actor');
    api.failure = BackendApiException('Auth rechazó',
        statusCode: 400, code: 'auth_user_create_failed',);
    await expectLater(repo.createPeople('teachers', payload),
        throwsA(isA<BackendApiException>()),);
    final first = api.requests.single['requestId'];
    api.failure = null;
    await repo.createPeople('teachers', payload);
    expect(api.requests.last['requestId'], isNot(first));
    await repo.updatePeople('students', '1', {'firstName': 'Updated'});
    expect(api.requests.last, {'firstName': 'Updated'});
  });
  test('a disposed repository cannot send a creation under another session',
      () async {
    final api = Api(),
        repo = AdminBackendRepository(api, creationScope: '1:actor');
    repo.dispose();
    await expectLater(repo.createPeople('students', payload), throwsStateError);
    expect(api.requests, isEmpty);
  });
}
