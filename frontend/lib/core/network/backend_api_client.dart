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

  Future<dynamic> call(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    final token = _supabase.auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) {
      throw StateError('Sesión requerida para llamar al backend.');
    }

    try {
      final response = await _dio.post<dynamic>(
        Env.businessApiUrl,
        data: {
          'action': action,
          'payload': payload,
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'apikey': Env.supabaseAnonKey,
            'Content-Type': 'application/json',
          },
        ),
      );

      final data = response.data;
      if (data is Map && data['ok'] == true) {
        return data['data'];
      }
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
