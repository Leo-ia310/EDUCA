import '../../../../core/network/backend_api_client.dart';
import '../../../../core/network/paginated_response.dart';
import '../models/sync_entry.dart';

typedef JsonMap = Map<String, dynamic>;

class BackendSyncRepository {
  BackendSyncRepository(this._api);

  final BackendApiClient _api;

  Future<PaginatedResponse<JsonMap>> listQueue({
    String? status,
    int page = 1,
    int pageSize = 100,
  }) async {
    final data = await _api.get(
      '/sync/queue',
      queryParameters: {
        'status': status,
        'page': page,
        'pageSize': pageSize,
      },
    );
    return PaginatedResponse.fromMap(data, (map) => map);
  }

  Future<JsonMap> enqueue(SyncEntry entry) async {
    final data = await _api.post(
      '/sync/queue',
      data: {
        'tableName': entry.tableName,
        'operation': entry.operation.toLowerCase(),
        'recordUuid': entry.recordUuid,
        'payload': entry.payload,
        'clientTimestamp':
            DateTime.fromMillisecondsSinceEpoch(entry.createdAtMs)
                .toIso8601String(),
      },
    );
    final map = (data as Map).cast<String, dynamic>();
    return (map['item'] as Map?)?.cast<String, dynamic>() ?? map;
  }

  Future<JsonMap> retry(int id) async {
    final data = await _api.post('/sync/queue/$id/retry');
    final map = (data as Map).cast<String, dynamic>();
    return (map['item'] as Map?)?.cast<String, dynamic>() ?? map;
  }

  Future<JsonMap> markFailed(int id, {String? error}) async {
    final data = await _api.post(
      '/sync/queue/$id/failed',
      data: {
        'error': error,
      },
    );
    final map = (data as Map).cast<String, dynamic>();
    return (map['item'] as Map?)?.cast<String, dynamic>() ?? map;
  }

  Future<JsonMap> pullChanges({
    DateTime? since,
    int page = 1,
    int pageSize = 500,
  }) async {
    final data = await _api.get(
      '/sync/changes',
      queryParameters: {
        'since': since?.toIso8601String(),
        'page': page,
        'pageSize': pageSize,
      },
    );
    return (data as Map).cast<String, dynamic>();
  }
}
