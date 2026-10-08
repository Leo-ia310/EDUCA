import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/backend_api_client.dart';
import '../../../core/network/paginated_response.dart';
import '../../auth/presentation/auth_controller.dart';

typedef JsonMap = Map<String, dynamic>;

class AdminBackendRepository {
  AdminBackendRepository(this._api);

  final BackendApiClient _api;

  Future<PaginatedResponse<JsonMap>> listInstitutions({
    String? search,
    bool? active,
    int page = 1,
    int pageSize = 50,
  }) async {
    final data = await _api.get(
      '/admin/institutions',
      queryParameters: {
        'search': search,
        'active': active,
        'page': page,
        'pageSize': pageSize,
      },
    );
    return _page(data);
  }

  Future<JsonMap> createInstitution(JsonMap payload) async => _entity(
        await _api.post('/admin/institutions', data: payload),
        'institution',
      );

  Future<JsonMap> updateInstitution(String id, JsonMap payload) async =>
      _entity(
        await _api.patch('/admin/institutions/$id', data: payload),
        'institution',
      );

  Future<JsonMap> archiveInstitution(String id) async => _entity(
        await _api.delete('/admin/institutions/$id'),
        'institution',
      );

  Future<PaginatedResponse<JsonMap>> listUsers({
    int? institutionId,
    String? search,
    bool? active,
    int page = 1,
    int pageSize = 50,
  }) async {
    final data = await _api.get(
      '/admin/users',
      queryParameters: {
        'institutionId': institutionId,
        'search': search,
        'active': active,
        'page': page,
        'pageSize': pageSize,
      },
    );
    return _page(data);
  }

  Future<JsonMap> createUser(JsonMap payload) async => _entity(
        await _api.post('/admin/users', data: payload),
        'user',
      );

  Future<JsonMap> updateUser(String id, JsonMap payload) async => _entity(
        await _api.patch('/admin/users/$id', data: payload),
        'user',
      );

  Future<JsonMap> archiveUser(String id, {int? institutionId}) async => _entity(
        await _api.delete(
          '/admin/users/$id',
          queryParameters: {
            'institutionId': institutionId,
          },
        ),
        'user',
      );

  Future<PaginatedResponse<JsonMap>> listRoles({
    int? institutionId,
    int page = 1,
    int pageSize = 50,
  }) async {
    final data = await _api.get(
      '/admin/roles',
      queryParameters: {
        'institutionId': institutionId,
        'page': page,
        'pageSize': pageSize,
      },
    );
    return _page(data);
  }

  Future<JsonMap> createRole(JsonMap payload) async => _entity(
        await _api.post('/admin/roles', data: payload),
        'role',
      );

  Future<JsonMap> updateRole(String id, JsonMap payload) async => _entity(
        await _api.patch('/admin/roles/$id', data: payload),
        'role',
      );

  Future<JsonMap> archiveRole(String id, {int? institutionId}) async => _entity(
        await _api.delete(
          '/admin/roles/$id',
          queryParameters: {
            'institutionId': institutionId,
          },
        ),
        'role',
      );

  Future<PaginatedResponse<JsonMap>> listPeople(
    String resource, {
    int? institutionId,
    String? search,
    bool? active,
    int page = 1,
    int pageSize = 50,
  }) async {
    _assertPeopleResource(resource);
    final data = await _api.get(
      '/admin/$resource',
      queryParameters: {
        'institutionId': institutionId,
        'search': search,
        'active': active,
        'page': page,
        'pageSize': pageSize,
      },
    );
    return _page(data);
  }

  Future<JsonMap> createPeople(String resource, JsonMap payload) async {
    _assertPeopleResource(resource);
    return _entity(
      await _api.post('/admin/$resource', data: payload),
      _key(resource),
    );
  }

  Future<JsonMap> updatePeople(
    String resource,
    String id,
    JsonMap payload,
  ) async {
    _assertPeopleResource(resource);
    return _entity(
      await _api.patch('/admin/$resource/$id', data: payload),
      _key(resource),
    );
  }

  Future<JsonMap> archivePeople(
    String resource,
    String id, {
    int? institutionId,
  }) async {
    _assertPeopleResource(resource);
    return _entity(
      await _api.delete(
        '/admin/$resource/$id',
        queryParameters: {
          'institutionId': institutionId,
        },
      ),
      _key(resource),
    );
  }

  PaginatedResponse<JsonMap> _page(dynamic data) {
    return PaginatedResponse<JsonMap>.fromMap(data, (map) => map);
  }

  JsonMap _entity(dynamic data, String key) {
    final map = (data as Map?)?.cast<String, dynamic>() ?? const {};
    return (map[key] as Map?)?.cast<String, dynamic>() ?? map;
  }

  String _key(String resource) => switch (resource) {
        'students' => 'student',
        'teachers' => 'teacher',
        'parents' => 'parent',
        _ => 'item',
      };

  void _assertPeopleResource(String resource) {
    if (resource != 'students' &&
        resource != 'teachers' &&
        resource != 'parents') {
      throw ArgumentError.value(
        resource,
        'resource',
        'Recurso admin inválido.',
      );
    }
  }
}

final adminBackendRepositoryProvider = Provider<AdminBackendRepository?>((ref) {
  final api = ref.watch(backendApiClientProvider);
  final auth = ref.watch(authControllerProvider);
  if (api == null || auth.institution == null) return null;
  return AdminBackendRepository(api);
});

final adminInstitutionsProvider =
    FutureProvider<PaginatedResponse<JsonMap>>((ref) async {
  final repo = ref.watch(adminBackendRepositoryProvider);
  if (repo == null) {
    return PaginatedResponse(
      items: const [],
      pageInfo: PageInfo.fromMap(const {'page': 1, 'pageSize': 50}),
    );
  }
  return repo.listInstitutions();
});

final adminUsersProvider =
    FutureProvider<PaginatedResponse<JsonMap>>((ref) async {
  final repo = ref.watch(adminBackendRepositoryProvider);
  if (repo == null) {
    return PaginatedResponse(
      items: const [],
      pageInfo: PageInfo.fromMap(const {'page': 1, 'pageSize': 50}),
    );
  }
  return repo.listUsers();
});
