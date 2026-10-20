import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/env.dart';
import 'supabase_client.dart';

class BackendApiException extends StateError {
  BackendApiException(super.message,
      {this.statusCode,
      this.code,
      this.retryable = false,
      this.requestId,
      this.retryAfter,});
  final int? statusCode;
  final String? code;
  final bool retryable;
  final String? requestId;
  final Duration? retryAfter;
}

/// HTTP failures retain retry/correlation information. Mutations are never
/// automatically retried: their caller owns a stable operation key.
class BackendApiClient {
  BackendApiClient({required SupabaseClient supabase, Dio? dio})
      : _supabase = supabase,
        _dio = dio ?? Dio() {
    _dio.options.connectTimeout ??= const Duration(seconds: 15);
    _dio.options.sendTimeout ??= const Duration(seconds: 30);
    _dio.options.receiveTimeout ??= const Duration(seconds: 75);
    _identity = _supabase.auth.currentSession?.user.id;
    _authSubscription = _supabase.auth.onAuthStateChange.listen(
      (event) {
        final identity = event.session?.user.id;
        if (identity != _identity) {
          _identity = identity;
          for (final entry in _active.entries.toList()) {
            if (entry.value) entry.key.cancel('session_changed');
          }
        }
      },
      onError: (Object error, StackTrace stack) {
        // The auth owner presents refresh failures. Only identity events affect
        // HTTP cancellation; a transient stream error does not switch accounts.
      },
    );
  }
  final SupabaseClient _supabase;
  final Dio _dio;
  final _active = <CancelToken, bool>{};
  StreamSubscription<AuthState>? _authSubscription;
  String? _identity;
  bool _disposed = false;

  String get _base {
    final value = Env.backendApiBaseUrl.trim();
    return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
  }

  Future<dynamic> call(String action,
          [Map<String, dynamic> payload = const {},]) =>
      post('/business-api', data: {'action': action, 'payload': payload});
  Future<dynamic> get(String path,
          {Map<String, dynamic>? queryParameters, bool authenticated = true,}) =>
      _request('GET', path,
          query: queryParameters, authenticated: authenticated,);
  Future<dynamic> post(String path,
          {Map<String, dynamic>? data,
          Map<String, dynamic>? queryParameters,
          bool authenticated = true,}) =>
      _request('POST', path,
          data: data ?? const {},
          query: queryParameters,
          authenticated: authenticated,);
  Future<dynamic> patch(String path,
          {Map<String, dynamic>? data,
          Map<String, dynamic>? queryParameters,
          bool authenticated = true,}) =>
      _request('PATCH', path,
          data: data ?? const {},
          query: queryParameters,
          authenticated: authenticated,);
  Future<dynamic> delete(String path,
          {Map<String, dynamic>? data,
          Map<String, dynamic>? queryParameters,
          bool authenticated = true,}) =>
      _request('DELETE', path,
          data: data, query: queryParameters, authenticated: authenticated,);

  Future<dynamic> _request(String method, String path,
      {Map<String, dynamic>? data,
      Map<String, dynamic>? query,
      required bool authenticated,}) async {
    if (_disposed) {
      throw BackendApiException('La sesión HTTP terminó.',
          code: 'request_cancelled',);
    }
    final identity = _supabase.auth.currentSession?.user.id;
    final headers = <String, String>{
      if (Env.supabaseAnonKey.isNotEmpty) 'apikey': Env.supabaseAnonKey,
      'Content-Type': 'application/json',
    };
    if (authenticated) {
      final token = _supabase.auth.currentSession?.accessToken;
      if (token == null || token.isEmpty) {
        throw BackendApiException('Sesión requerida para llamar al backend.',
            statusCode: 401, code: 'session_required',);
      }
      headers['Authorization'] = 'Bearer $token';
    }
    final cancel = CancelToken();
    _active[cancel] = authenticated;
    try {
      final result = await _unwrap(
        _dio.request<dynamic>(
          '$_base${path.startsWith('/') ? path : '/$path'}',
          data: data,
          queryParameters: query == null
              ? null
              : Map<String, dynamic>.fromEntries(
                  query.entries.where((entry) => entry.value != null),),
          options: Options(method: method, headers: headers),
          cancelToken: cancel,
        ),
      );
      if (_disposed ||
          authenticated && _supabase.auth.currentSession?.user.id != identity) {
        throw BackendApiException('La cuenta cambió durante la solicitud.',
            code: 'request_cancelled',);
      }
      return result;
    } finally {
      _active.remove(cancel);
    }
  }

  Future<dynamic> _unwrap(Future<Response<dynamic>> request) async {
    try {
      final response = await request;
      final data = response.data;
      if (data is Map && data['ok'] == true) return data['data'];
      throw _failure(response, 'Respuesta inválida del backend.',
          fallbackCode: 'invalid_response',);
    } on DioException catch (error) {
      final message = switch (error.type) {
        DioExceptionType.connectionError =>
          'No se pudo conectar con el servidor. Revisa tu conexión.',
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout =>
          'El servidor está tardando. No se pudo confirmar; reintenta la misma operación.',
        DioExceptionType.badCertificate =>
          'No se pudo establecer una conexión segura.',
        DioExceptionType.cancel => 'La solicitud se canceló.',
        _ => 'No se pudo completar la solicitud.',
      };
      if (error.response != null) throw _failure(error.response!, message);
      throw BackendApiException(
        message,
        code: error.type == DioExceptionType.cancel
            ? 'request_cancelled'
            : 'transport_error',
        retryable: [
          DioExceptionType.connectionError,
          DioExceptionType.connectionTimeout,
          DioExceptionType.sendTimeout,
          DioExceptionType.receiveTimeout,
        ].contains(error.type),
      );
    }
  }

  BackendApiException _failure(Response<dynamic> response, String fallback,
      {String? fallbackCode,}) {
    final data = response.data;
    final error = data is Map ? data['error'] : null;
    final status = response.statusCode;
    final requestId = error is Map ? error['requestId']?.toString() : null;
    return BackendApiException(
      error is Map && error['message'] is String
          ? error['message'] as String
          : fallback,
      statusCode: status,
      code: error is Map
          ? error['code']?.toString() ?? fallbackCode
          : fallbackCode,
      requestId: requestId ?? response.headers.value('x-request-id'),
      retryAfter: _retryAfter(response.headers.value('retry-after')),
      retryable: status == 429 ||
          status != null && status >= 500 ||
          fallbackCode == 'invalid_response',
    );
  }

  Duration? _retryAfter(String? raw) {
    if (raw == null) return null;
    final seconds = int.tryParse(raw);
    if (seconds != null) return Duration(seconds: seconds.clamp(0, 86400));
    try {
      final date =
          DateFormat("EEE, dd MMM yyyy HH:mm:ss 'GMT'", 'en_US').parseUtc(raw);
      return Duration(
          milliseconds: date
              .difference(DateTime.now().toUtc())
              .inMilliseconds
              .clamp(0, 86400000),);
    } on FormatException {
      return null;
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final cancel in _active.keys.toList()) {
      cancel.cancel('client_disposed');
    }
    unawaited(_authSubscription?.cancel());
    _authSubscription = null;
    _dio.close(force: true);
  }
}

final backendApiClientProvider = Provider<BackendApiClient?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return null;
  final api = BackendApiClient(supabase: client);
  ref.onDispose(api.dispose);
  return api;
});
