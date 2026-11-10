import '../../../core/network/backend_api_client.dart';
import 'originality_report.dart';
import 'originality_summary.dart';

/// Acceso HTTP a Nivra Originality (solo perfil docente).
class OriginalityApi {
  const OriginalityApi(this._api);
  final BackendApiClient _api;

  Map<String, dynamic> _map(dynamic data) =>
      Map<String, dynamic>.from(data as Map);

  Future<OriginalitySummary> summary(String assignmentId) async =>
      OriginalitySummary.fromJson(
        _map(
          await _api.get('/assignments/$assignmentId/originality/summary'),
        ),
      );

  Future<OriginalityTemplate> template(String assignmentId) async =>
      OriginalityTemplate.fromJson(
        _map(await _api.get('/assignments/$assignmentId/originality/template')),
      );

  /// Guarda la plantilla; devuelve cuántos documentos se reanalizan.
  Future<int> saveTemplate(String assignmentId, String template) async {
    final data = _map(
      await _api.post(
        '/assignments/$assignmentId/originality/template',
        data: {'template': template},
      ),
    );
    return (data['reanalyzing'] as num?)?.toInt() ?? 0;
  }

  Future<OriginalityReport> report(
    String submissionId, {
    bool evidence = false,
  }) async =>
      OriginalityReport.fromJson(
        _map(
          await _api.get(
            '/assignments/submissions/$submissionId/originality',
            queryParameters: {'evidence': evidence ? 'true' : 'false'},
          ),
        ),
      );

  Future<OriginalityReport> retry(String submissionId) async =>
      OriginalityReport.fromJson(
        _map(
          await _api.post(
            '/assignments/submissions/$submissionId/originality/retry',
            data: <String, dynamic>{},
          ),
        ),
      );
}
