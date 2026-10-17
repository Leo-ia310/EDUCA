import 'package:dio/dio.dart';
import 'package:educa360/core/network/backend_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
    dio.close(force: true);
    await supabase.dispose();
  });

  for (final type in [
    DioExceptionType.connectionError,
    DioExceptionType.connectionTimeout,
    DioExceptionType.unknown,
  ]) {
    test('login network failure $type has no raw browser diagnostics',
        () async {
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) => handler.reject(DioException(
          requestOptions: options,
          type: type,
          message: 'XMLHttpRequest onError callback CORS internal diagnostic',
        ),),
      ),);
      await expectLater(
        api.post('/auth/login', authenticated: false),
        throwsA(isA<StateError>().having(
          (error) => error.message,
          'safe Spanish message',
          allOf(
              startsWith(type == DioExceptionType.connectionTimeout
                  ? 'El servidor'
                  : 'No se pudo',),
              isNot(contains('XMLHttpRequest')),
              isNot(contains('CORS')),),
        ),),
      );
    });
  }

  test('login preserves the controlled invalid credentials response', () async {
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) => handler.reject(DioException(
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
      ),),
    ),);
    await expectLater(
      api.post('/auth/login', authenticated: false),
      throwsA(isA<StateError>().having(
        (error) => error.message,
        'server message',
        'Credenciales incorrectas.',
      ),),
    );
  });
}
