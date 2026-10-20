import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/backend_api_client.dart';
import '../../../core/network/paginated_response.dart';
import '../../../shared/models/app_role.dart';
import '../../auth/presentation/auth_controller.dart';
import 'admin_profile.dart';
import 'admin_schedule.dart';
import 'demo_schedules.dart';
import 'school_directory.dart';

typedef JsonMap = Map<String, dynamic>;

class AdminCatalogPage {
  const AdminCatalogPage({required this.directory, required this.pageInfo});
  final SchoolDirectory directory;
  final PageInfo pageInfo;
}

class AdminBackendRepository {
  AdminBackendRepository(this._api, {String? creationScope})
      : _creationScope = creationScope;
  final String? _creationScope;
  bool _disposed = false;
  void dispose() {
    _disposed = true;
  }

  final BackendApiClient _api;

  Future<dynamic> _createAccess(
      String kind, String path, JsonMap payload,) async {
    final scope = _creationScope;
    if (scope == null && payload['requestId'] == null) {
      throw StateError('Se requiere contexto de cuenta para crear un acceso.');
    }
    final prefs = scope == null ? null : await SharedPreferences.getInstance();
    final slot = 'admin.creation.v1.${Uri.encodeComponent(jsonEncode([
          scope,
          kind,
          payload['email'].toString().trim().toLowerCase(),
        ]),)}';
    final storedKey = prefs?.getString(slot);
    if (storedKey != null &&
        payload['requestId'] != null &&
        payload['requestId'] != storedKey) {
      throw StateError(
          'Ya hay una solicitud pendiente para este acceso. Reintenta con su clave original.',);
    }
    final key =
        payload['requestId'] as String? ?? storedKey ?? const Uuid().v4();
    if (prefs != null && !await prefs.setString(slot, key)) {
      throw StateError(
          'No se pudo conservar la solicitud de alta en este dispositivo.',);
    }
    final data = {...payload, 'requestId': key};
    if (kind == 'students') data.putIfAbsent('studentCode', () => 'EST-$key');
    if (kind == 'teachers') data.putIfAbsent('teacherCode', () => 'DOC-$key');
    try {
      if (_disposed) {
        throw StateError('La sesión cambió antes de enviar la solicitud.');
      }
      final result = await _api.post(path, data: data);
      if (prefs?.getString(slot) == key) await prefs!.remove(slot);
      return result;
    } on BackendApiException catch (error) {
      // Only a confirmed Auth rejection retires the reservation. Timeouts and
      // ambiguous SQL results retain the same key across navigation/restarts.
      if (error.code == 'auth_user_create_failed' &&
          prefs?.getString(slot) == key) {
        await prefs!.remove(slot);
      }
      rethrow;
    }
  }

  Future<JsonMap> directoryOptions(
    String kind, {
    String? search,
    int page = 1,
    Set<String> includeIds = const {},
  }) async {
    return Map<String, dynamic>.from(
      await _api.get(
        '/admin/directory/options',
        queryParameters: {
          'kind': kind,
          'search': search,
          'page': page,
          'pageSize': 50,
          if (includeIds.isNotEmpty)
            'includeIds': includeIds.take(100).join(','),
        },
      ) as Map,
    );
  }

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
    String? id,
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
        'id': id,
        'institutionId': institutionId,
        'search': search,
        'active': active,
        'page': page,
        'pageSize': pageSize,
      },
    );
    return _page(data);
  }

  Future<Person> personDirectoryDetail(AppRole role, String id) async {
    final resource = switch (role) {
      AppRole.teacher => 'teachers',
      AppRole.parent => 'parents',
      _ => 'students'
    };
    final page = await listPeople(resource, id: id, pageSize: 1);
    if (page.items.isEmpty) throw StateError('Registro no encontrado.');
    return _directoryPerson(page.items.single, const []);
  }

  Future<PaginatedResponse<Person>> directoryPeoplePage({
    AppRole? role,
    String? search,
    int page = 1,
    String? groupId,
  }) async {
    final data = await _api.get(
      '/admin/directory/people',
      queryParameters: {
        'role': role?.code ?? 'all',
        'search': search,
        'page': page,
        'pageSize': 50,
        'groupId': groupId,
      },
    );
    return PaginatedResponse<Person>.fromMap(
      data,
      (row) => _directoryPerson(row, const []),
    );
  }

  Future<PaginatedResponse<AdminProfile>> listProfiles({
    int? institutionId,
    String? search,
    int page = 1,
  }) async {
    final data = await _api.get(
      '/admin/profiles',
      queryParameters: {
        'institutionId': institutionId,
        'search': search,
        'page': page,
        'pageSize': 50,
      },
    );
    final map = (data as Map).cast<String, dynamic>();
    return PaginatedResponse<AdminProfile>.fromMap(
      {'items': map['profiles'], 'pageInfo': map['pageInfo']},
      AdminProfile.fromJson,
    );
  }

  Future<Map<String, int>> directoryCounts() async {
    final data = await _api.get('/admin/directory/counts') as Map;
    return Map<String, dynamic>.from(data['counts'] as Map)
        .map((key, value) => MapEntry(key, (value as num).toInt()));
  }

  Future<AdminProfile> createProfile(JsonMap payload) async {
    final data = await _createAccess('profile', '/admin/profiles', payload);
    return AdminProfile.fromJson(
      ((data as Map)['profile'] as Map).cast<String, dynamic>(),
    );
  }

  Future<AdminProfile> updateProfile(String id, JsonMap payload) async {
    final data = await _api.patch('/admin/profiles/$id', data: payload);
    return AdminProfile.fromJson(
      ((data as Map)['profile'] as Map).cast<String, dynamic>(),
    );
  }

  Future<PaginatedResponse<AdminScheduleEntry>> schedulesPage({
    String? groupId,
    int? weekdayId,
    int page = 1,
  }) async {
    final data = await _api.get(
      '/schedules',
      queryParameters: {
        'groupId': groupId,
        'weekdayId': weekdayId,
        'page': page,
        'pageSize': 50,
      },
    );
    final map = (data as Map).cast<String, dynamic>();
    return PaginatedResponse<AdminScheduleEntry>.fromMap(
      {'items': map['schedules'], 'pageInfo': map['pageInfo']},
      AdminScheduleEntry.fromJson,
    );
  }

  /// Crea el horario en uno o varios días (`weekdayIds`) y devuelve lo creado.
  Future<List<AdminScheduleEntry>> createSchedules(JsonMap payload) async {
    final data = await _api.post('/schedules', data: payload);
    final map = (data as Map).cast<String, dynamic>();
    return [
      for (final row in (map['schedules'] as List? ?? const []))
        AdminScheduleEntry.fromJson((row as Map).cast<String, dynamic>()),
    ];
  }

  Future<AdminScheduleEntry> updateSchedule(String id, JsonMap payload) async {
    final data = await _api.patch('/schedules/$id', data: payload);
    return AdminScheduleEntry.fromJson(
      ((data as Map)['schedule'] as Map).cast<String, dynamic>(),
    );
  }

  Future<void> deleteSchedule(String id) async {
    await _api.delete('/schedules/$id');
  }

  Future<AdminCatalogPage> directoryPage({
    int? institutionId,
    String kind = 'classes',
    String? search,
    int page = 1,
    String? groupId,
  }) async {
    final data = await _api.get(
      '/admin/directory',
      queryParameters: {
        'institutionId': institutionId,
        'kind': kind,
        'search': search,
        'page': page,
        'pageSize': 50,
        'groupId': groupId,
      },
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
    return AdminCatalogPage(
      directory:
          SchoolDirectory(people: people, groups: groups, classes: classes),
      pageInfo: PageInfo.fromMap(
        Map<String, dynamic>.from(map['pageInfo'] as Map),
      ),
    );
  }

  Future<SchoolDirectory> listDirectory({int? institutionId}) async =>
      (await directoryPage(institutionId: institutionId)).directory;

  Future<JsonMap> createPeople(String resource, JsonMap payload) async {
    _assertPeopleResource(resource);
    return _entity(
      await _createAccess(resource, '/admin/$resource', payload),
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
    groupName: row['group_name'] as String?,
    classLabels: ((row['classes'] as List?) ?? const []).map((value) {
      final c = value as Map;
      return '${c['subject'] ?? 'Materia'} (${c['groupName'] ?? '—'})';
    }).toList(),
    childNames: ((row['children'] as List?) ?? const [])
        .map((value) => (value as Map)['name']?.toString() ?? 'Estudiante')
        .toList(),
  );
}

SchoolGroup _directoryGroup(JsonMap row) {
  return SchoolGroup(
    id: row['id']?.toString() ?? '',
    name: row['name']?.toString() ?? 'Sin nombre',
    studentCount: (row['student_count'] as num?)?.toInt(),
    classCount: (row['class_count'] as num?)?.toInt(),
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
  if (api == null || auth.institution == null || auth.user == null) return null;
  final repository = AdminBackendRepository(api,
      creationScope: '${auth.institution!.id}:${auth.user!.id}',);
  ref.onDispose(repository.dispose);
  return repository;
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

final adminProfilesProvider = FutureProvider.autoDispose
    .family<PaginatedResponse<AdminProfile>, ({String search, int page})>(
        (ref, query) async {
  final repo = ref.watch(adminBackendRepositoryProvider);
  if (repo == null) {
    return PaginatedResponse(
      items: const [],
      pageInfo: PageInfo.fromMap(const {}),
    );
  }
  return repo.listProfiles(search: query.search, page: query.page);
});

final adminDirectoryCountsProvider =
    FutureProvider.autoDispose<Map<String, int>>((ref) async {
  return await ref.watch(adminBackendRepositoryProvider)?.directoryCounts() ??
      const {};
});

typedef AdminScheduleQuery = ({String? groupId, int? weekdayId, int page});
final adminSchedulesProvider = FutureProvider.autoDispose
    .family<PaginatedResponse<AdminScheduleEntry>, AdminScheduleQuery>(
        (ref, query) async {
  final repo = ref.watch(adminBackendRepositoryProvider);
  if (repo != null) {
    return repo.schedulesPage(
      groupId: query.groupId,
      weekdayId: query.weekdayId,
      page: query.page,
    );
  }
  final items = ref
      .watch(demoSchedulesProvider)
      .where(
        (s) =>
            (query.groupId == null ||
                s.groupId == null ||
                s.groupId == query.groupId) &&
            (query.weekdayId == null || s.weekdayId == query.weekdayId),
      )
      .toList();
  return PaginatedResponse(
    items: items,
    pageInfo: PageInfo(
      page: 1,
      pageSize: items.length,
      total: items.length,
      totalPages: 1,
      hasNextPage: false,
      hasPreviousPage: false,
    ),
  );
});

final adminSchoolDirectoryProvider =
    FutureProvider.autoDispose<SchoolDirectory>((ref) async {
  final repo = ref.watch(adminBackendRepositoryProvider);
  if (repo == null) return ref.watch(schoolDirectoryProvider);
  return repo.listDirectory();
});

typedef AdminCatalogQuery = ({
  String kind,
  String search,
  int page,
  String? groupId
});
final adminCatalogProvider = FutureProvider.autoDispose
    .family<AdminCatalogPage, AdminCatalogQuery>((ref, query) async {
  final repository = ref.watch(adminBackendRepositoryProvider);
  if (repository == null) {
    return AdminCatalogPage(
      directory: ref.watch(schoolDirectoryProvider),
      pageInfo: PageInfo.fromMap(const {}),
    );
  }
  return repository.directoryPage(
    kind: query.kind,
    search: query.search,
    page: query.page,
    groupId: query.groupId,
  );
});

typedef AdminPeopleQuery = ({AppRole role, String search, int page});
typedef AdminDirectoryPeopleQuery = ({
  AppRole? role,
  String search,
  int page,
  String? groupId
});
final adminDirectoryPeoplePageProvider = FutureProvider.autoDispose
    .family<PaginatedResponse<Person>, AdminDirectoryPeopleQuery>(
        (ref, query) async {
  final repository = ref.watch(adminBackendRepositoryProvider);
  if (repository == null) {
    return PaginatedResponse(
      items: const [],
      pageInfo: PageInfo.fromMap(const {}),
    );
  }
  return repository.directoryPeoplePage(
    role: query.role,
    search: query.search,
    page: query.page,
    groupId: query.groupId,
  );
});
final adminPeoplePageProvider = FutureProvider.autoDispose
    .family<PaginatedResponse<Person>, AdminPeopleQuery>((ref, query) async {
  final repository = ref.watch(adminBackendRepositoryProvider);
  if (repository == null) {
    return PaginatedResponse(
      items: const [],
      pageInfo: PageInfo.fromMap(const {'page': 1, 'pageSize': 50}),
    );
  }
  final resource = switch (query.role) {
    AppRole.teacher => 'teachers',
    AppRole.parent => 'parents',
    _ => 'students'
  };
  final page = await repository.listPeople(
    resource,
    search: query.search,
    page: query.page,
  );
  return PaginatedResponse(
    items: page.items.map((row) => _directoryPerson(row, const [])).toList(),
    pageInfo: page.pageInfo,
  );
});
