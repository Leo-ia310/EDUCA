import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/backend_api_client.dart';
import '../../../core/network/paginated_response.dart';
import '../../../shared/models/app_role.dart';
import '../../auth/presentation/auth_controller.dart';
import 'school_directory.dart';

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

  Future<SchoolDirectory> listDirectory({int? institutionId}) async {
    final data = await _api.get(
      '/admin/directory',
      queryParameters: {'institutionId': institutionId},
    );
    final map = (data as Map).cast<String, dynamic>();
    final groups = ((map['groups'] as List?) ?? const [])
        .map((row) => _directoryGroup((row as Map).cast<String, dynamic>()))
        .toList();
    final classes = ((map['classes'] as List?) ?? const [])
        .map((row) => _directoryClass((row as Map).cast<String, dynamic>()))
        .toList();
    final people = ((map['people'] as List?) ?? const [])
        .map(
          (row) => _directoryPerson(
            (row as Map).cast<String, dynamic>(),
            classes,
          ),
        )
        .toList();
    return SchoolDirectory(people: people, groups: groups, classes: classes);
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

  Future<JsonMap> createGroup(JsonMap payload) async => _entity(
        await _api.post('/admin/groups', data: payload),
        'group',
      );

  Future<JsonMap> updateGroup(String id, JsonMap payload) async => _entity(
        await _api.patch('/admin/groups/$id', data: payload),
        'group',
      );

  Future<JsonMap> archiveGroup(String id, {int? institutionId}) async =>
      _entity(
        await _api.delete(
          '/admin/groups/$id',
          queryParameters: {'institutionId': institutionId},
        ),
        'group',
      );

  Future<JsonMap> createClass(JsonMap payload) async => _entity(
        await _api.post('/admin/classes', data: payload),
        'class',
      );

  Future<JsonMap> updateClass(String id, JsonMap payload) async => _entity(
        await _api.patch('/admin/classes/$id', data: payload),
        'class',
      );

  Future<JsonMap> archiveClass(String id, {int? institutionId}) async =>
      _entity(
        await _api.delete(
          '/admin/classes/$id',
          queryParameters: {'institutionId': institutionId},
        ),
        'class',
      );

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

Person _directoryPerson(JsonMap row, List<SchoolClass> classes) {
  final person = (row['persons'] as Map?)?.cast<String, dynamic>() ??
      const <String, dynamic>{};
  final role = AppRole.fromCode(row['role']?.toString()) ?? AppRole.student;
  final first = person['first_name']?.toString() ?? '';
  final last = person['last_name']?.toString() ?? '';
  final fullName =
      [first, last].where((part) => part.trim().isNotEmpty).join(' ').trim();
  final groupId = row['group_id']?.toString();
  final backendClassIds = ((row['class_ids'] as List?) ?? const [])
      .map((value) => value.toString())
      .toSet();
  final classIds = backendClassIds.isNotEmpty || groupId == null
      ? backendClassIds
      : classes
          .where((schoolClass) => schoolClass.groupId == groupId)
          .map((schoolClass) => schoolClass.id)
          .toSet();
  final childIds = ((row['child_ids'] as List?) ?? const [])
      .map((value) => value.toString())
      .toSet();
  return Person(
    id: row['id']?.toString() ?? '',
    name: fullName.isEmpty ? 'Sin nombre' : fullName,
    role: role,
    email: person['email']?.toString() ?? '',
    phone: person['phone']?.toString() ?? '',
    active: row['active'] != false,
    groupId: groupId,
    classIds: classIds,
    childIds: childIds,
  );
}

SchoolGroup _directoryGroup(JsonMap row) {
  return SchoolGroup(
    id: row['id']?.toString() ?? '',
    name: row['name']?.toString() ?? 'Sin nombre',
  );
}

SchoolClass _directoryClass(JsonMap row) {
  final subject = (row['subjects'] as Map?)?.cast<String, dynamic>();
  final group = (row['groups'] as Map?)?.cast<String, dynamic>();
  final classroom = (group?['classrooms'] as Map?)?.cast<String, dynamic>();
  return SchoolClass(
    id: row['id']?.toString() ?? '',
    subject: subject?['name']?.toString() ?? 'Materia',
    groupId: row['group_id']?.toString() ?? '',
    teacherId: row['teacher_id']?.toString(),
    room: classroom?['name']?.toString() ?? '',
  );
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

final adminSchoolDirectoryProvider =
    FutureProvider<SchoolDirectory>((ref) async {
  final repo = ref.watch(adminBackendRepositoryProvider);
  if (repo == null) return ref.watch(schoolDirectoryProvider);
  return repo.listDirectory();
});

final adminPeopleByRoleProvider =
    FutureProvider.family<List<Person>, AppRole>((ref, role) async {
  final repo = ref.watch(adminBackendRepositoryProvider);
  if (repo == null) return const [];
  final resource = switch (role) {
    AppRole.teacher => 'teachers',
    AppRole.student => 'students',
    AppRole.parent => 'parents',
    _ => null,
  };
  if (resource == null) return const [];
  final page = await repo.listPeople(resource, pageSize: 100);
  return page.items.map((row) => _personFromBackend(row, role)).toList();
});

Person _personFromBackend(JsonMap row, AppRole role) {
  final person = (row['persons'] as Map?)?.cast<String, dynamic>() ??
      (row['person'] as Map?)?.cast<String, dynamic>() ??
      const <String, dynamic>{};
  final first = person['first_name']?.toString() ?? '';
  final last = person['last_name']?.toString() ?? '';
  final fullName =
      [first, last].where((part) => part.trim().isNotEmpty).join(' ');
  return Person(
    id: row['id']?.toString() ?? '',
    name: fullName.trim().isEmpty ? 'Sin nombre' : fullName,
    role: role,
    email: person['email']?.toString() ?? '',
    phone: person['phone']?.toString() ?? '',
    active: row['active'] != false,
  );
}
