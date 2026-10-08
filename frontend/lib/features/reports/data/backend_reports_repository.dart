import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/backend_api_client.dart';
import '../../auth/presentation/auth_controller.dart';

typedef JsonMap = Map<String, dynamic>;

class BackendReportsRepository {
  BackendReportsRepository(this._api);

  final BackendApiClient _api;

  Future<JsonMap> previewReportCard({
    required int studentId,
    required int academicPeriodId,
  }) async {
    final data = await _api.get(
      '/reports/report-cards/preview',
      queryParameters: {
        'studentId': studentId,
        'academicPeriodId': academicPeriodId,
      },
    );
    return (data as Map).cast<String, dynamic>();
  }

  Future<JsonMap> generateReportCard({
    required int studentId,
    required int academicPeriodId,
    String? generalNotes,
  }) async {
    final data = await _api.post(
      '/reports/report-cards',
      data: {
        'studentId': studentId,
        'academicPeriodId': academicPeriodId,
        'generalNotes': generalNotes,
      },
    );
    final map = (data as Map).cast<String, dynamic>();
    return (map['reportCard'] as Map?)?.cast<String, dynamic>() ?? map;
  }

  Future<JsonMap> getReportCard(String id) async {
    final data = await _api.get('/reports/report-cards/$id');
    final map = (data as Map).cast<String, dynamic>();
    return (map['reportCard'] as Map?)?.cast<String, dynamic>() ?? map;
  }
}

final backendReportsRepositoryProvider =
    Provider<BackendReportsRepository?>((ref) {
  final api = ref.watch(backendApiClientProvider);
  final auth = ref.watch(authControllerProvider);
  if (api == null || auth.institution == null) return null;
  return BackendReportsRepository(api);
});
