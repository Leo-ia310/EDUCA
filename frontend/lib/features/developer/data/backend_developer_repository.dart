import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/env.dart';
import '../domain/developer_repository.dart';
import '../domain/entities.dart';

/// Implementación real: llama a las rutas REST `/api/developer/*` del backend
/// Node con el JWT del usuario. El backend valida `requireAdmin` y RLS antes de
/// tocar Postgres.
class BackendDeveloperRepository implements DeveloperRepository {
  BackendDeveloperRepository({required SupabaseClient supabase, Dio? dio})
      : _supabase = supabase,
        _dio = dio ?? Dio();

  final SupabaseClient _supabase;
  final Dio _dio;

  String get _base {
    final b = Env.backendApiBaseUrl.trim();
    return b.endsWith('/') ? b.substring(0, b.length - 1) : b;
  }

  Options get _authOptions {
    final token = _supabase.auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) {
      throw StateError('Sesión requerida para el panel de desarrollador.');
    }
    return Options(headers: {
      'Authorization': 'Bearer $token',
      'apikey': Env.supabaseAnonKey,
      'Content-Type': 'application/json',
    });
  }

  /// Ejecuta la petición y desenvuelve `{ ok, data }`.
  Future<dynamic> _unwrap(Future<Response<dynamic>> request) async {
    try {
      final res = await request;
      final data = res.data;
      if (data is Map && data['ok'] == true) return data['data'];
      throw StateError(_messageFrom(data) ?? 'Respuesta inválida del backend.');
    } on DioException catch (e) {
      throw StateError(
          _messageFrom(e.response?.data) ?? e.message ?? 'Error de red.');
    }
  }

  String? _messageFrom(dynamic data) {
    if (data is Map) {
      final err = data['error'];
      if (err is Map && err['message'] is String) {
        return err['message'] as String;
      }
      if (data['message'] is String) return data['message'] as String;
    }
    return null;
  }

  @override
  Future<DevSummary> summary() async {
    final data = await _unwrap(
      _dio.get('$_base/developer/summary', options: _authOptions),
    );
    return DevSummary.fromMap(devMap(data));
  }
}
