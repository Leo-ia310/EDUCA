import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/env.dart';
import 'supabase_client.dart';

/// Cliente HTTP para la capa de negocio del backend.
///
/// Mantiene Supabase Auth en el frontend, pero las escrituras sensibles viajan
/// al backend Node (`BACKEND_API_BASE_URL`), donde se validan roles,
/// pertenencia multi-tenant y reglas antes de tocar Postgres.
class BackendApiClient {
  BackendApiClient({
    required SupabaseClient supabase,
    Dio? dio,
  })  : _supabase = supabase,
        _dio = dio ?? Dio();

  final SupabaseClient _supabase;
  final Dio _dio;

  String get _base {
    final value = Env.backendApiBaseUrl.trim();
    return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
  }

  /// Compatibilidad con la API antigua `/api/business-api` basada en acciones.
  Future<dynamic> call(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    return post(
      '/business-api',
      data: {
        'action': action,
        'payload': payload,
      },
    );
  }

  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) {
    return _unwrap(
      _dio.get<dynamic>(
        _url(path),
        queryParameters: _cleanQuery(queryParameters),
        options: _options(authenticated: authenticated),
      ),
    );
  }

  Future<dynamic> post(
    String path, {
    Map<String, dynamic>? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) {
    return _unwrap(
      _dio.post<dynamic>(
        _url(path),
        data: data ?? const {},
        queryParameters: _cleanQuery(queryParameters),
        options: _options(authenticated: authenticated),
      ),
    );
  }

  Future<dynamic> patch(
    String path, {
    Map<String, dynamic>? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) {
    return _unwrap(
      _dio.patch<dynamic>(
        _url(path),
        data: data ?? const {},
        queryParameters: _cleanQuery(queryParameters),
        options: _options(authenticated: authenticated),
      ),
    );
  }

  Future<dynamic> delete(
    String path, {
    Map<String, dynamic>? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) {
    return _unwrap(
      _dio.delete<dynamic>(
        _url(path),
        data: data,
        queryParameters: _cleanQuery(queryParameters),
        options: _options(authenticated: authenticated),
      ),
    );
  }

  String _url(String path) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return '$_base$normalizedPath';
  }

  Options _options({required bool authenticated}) {
    final headers = <String, String>{
      if (Env.supabaseAnonKey.isNotEmpty) 'apikey': Env.supabaseAnonKey,
      'Content-Type': 'application/json',
    };
    if (authenticated) {
      final token = _supabase.auth.currentSession?.accessToken;
      if (token == null || token.isEmpty) {
        throw StateError('Sesión requerida para llamar al backend.');
      }
      headers['Authorization'] = 'Bearer $token';
    }
    return Options(headers: headers);
  }

  Map<String, dynamic>? _cleanQuery(Map<String, dynamic>? query) {
    if (query == null) return null;
    return Map<String, dynamic>.fromEntries(
      query.entries.where((entry) => entry.value != null),
    );
  }

  /// Ejecuta la petición y desenvuelve `{ ok, data }`.
  Future<dynamic> _unwrap(Future<Response<dynamic>> request) async {
    try {
      final response = await request;
      final data = response.data;
      if (data is Map && data['ok'] == true) return data['data'];
      throw StateError(_messageFrom(data) ?? 'Respuesta inválida del backend.');
    } on DioException catch (e) {
      final message = _messageFrom(e.response?.data) ?? e.message;
      throw StateError(message ?? 'No se pudo llamar al backend.');
    }
  }

  String? _messageFrom(dynamic data) {
    if (data is Map) {
      final error = data['error'];
      if (error is Map && error['message'] is String) {
        return error['message'] as String;
      }
      if (data['message'] is String) return data['message'] as String;
    }
    return null;
  }
}

final backendApiClientProvider = Provider<BackendApiClient?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return null;
  return BackendApiClient(supabase: client);
});
