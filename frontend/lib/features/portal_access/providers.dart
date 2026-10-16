import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/env.dart';
import '../../core/network/backend_api_client.dart';
import '../../core/network/supabase_client.dart';
import 'portal_access_sync.dart';
import '../auth/presentation/auth_controller.dart';
import '../../shared/models/app_role.dart';

const portalPermissionLabels = <String, String>{
  'grades.view': 'Ver notas',
  'payments.view': 'Ver pagos',
  'attendance.view': 'Ver asistencia',
  'schedule.view': 'Ver horario',
  'assignments.view': 'Ver tareas',
  'assignments.submit': 'Entregar tareas',
  'reports.view': 'Ver reportes',
  'reports.download': 'Descargar boletines',
  'announcements.view': 'Ver comunicados',
  'messages.send': 'Enviar mensajes',
  'materials.view': 'Ver materiales',
};

class PortalAccess {
  const PortalAccess({
    required this.permissions,
    this.students = const [],
    this.staff = false,
  });
  final Map<String, bool> permissions;
  final List<Map<String, dynamic>> students;
  final bool staff;
  bool can(String code) => staff || permissions[code] == true;
  bool gradeVisible(int studentId, String? periodId) {
    if (staff) return true;
    if (!can('grades.view')) return false;
    for (final student in students) {
      if (student['studentId'].toString() != studentId.toString()) continue;
      if (periodId == null) return student['annualVisible'] == true;
      return (student['periods'] as List)
          .any((p) => p['id'].toString() == periodId && p['visible'] == true);
    }
    return false;
  }

  bool get annualGradesVisible =>
      can('grades.view') &&
      (staff || students.every((s) => s['annualVisible'] == true));
  bool get anyGradesVisible =>
      can('grades.view') &&
      (staff ||
          students.isEmpty ||
          students.any(
            (s) =>
                s['annualVisible'] == true ||
                (s['periods'] as List).any((p) => p['visible'] == true),
          ));
  String get fingerprint => jsonEncode([permissions, students, staff]);
  factory PortalAccess.fromJson(Map<String, dynamic> json) => PortalAccess(
        staff: json['staff'] == true,
        permissions: Map<String, dynamic>.from(json['permissions'] as Map)
            .map((k, v) => MapEntry(k, v == true)),
        students: (json['students'] as List? ?? [])
            .map((s) => Map<String, dynamic>.from(s as Map))
            .toList(),
      );
  factory PortalAccess.unrestricted() => PortalAccess(
        staff: true,
        permissions: {
          for (final code in portalPermissionLabels.keys) code: true,
        },
      );
}

// Identity changes reload access; transient auth loading/error flags do not.
final portalAccessLoaderProvider =
    Provider<Future<PortalAccess> Function()>((ref) {
  final identity = ref.watch(authControllerProvider.select((auth) =>
      (auth.user?.id, auth.user?.institutionId, auth.user?.activeRole),),);
  if (Env.isDemoMode ||
      (identity.$1 != null &&
          ![AppRole.student, AppRole.parent].contains(identity.$3))) {
    return () async => PortalAccess.unrestricted();
  }
  final api = ref.watch(backendApiClientProvider);
  return () async {
    if (identity.$1 == null || api == null) {
      throw StateError('Inicia sesión para consultar tus accesos.');
    }
    return PortalAccess.fromJson(Map<String, dynamic>.from(
      await api.get('/portal-access/me') as Map,
    ),);
  };
});
final portalAccessChangesProvider = StreamProvider<void>((ref) {
  final identity = ref.watch(authControllerProvider.select((auth) =>
      (auth.user?.id, auth.user?.institutionId, auth.user?.activeRole),),);
  if (Env.isDemoMode ||
      identity.$1 == null ||
      ![AppRole.student, AppRole.parent].contains(identity.$3)) {
    return const Stream.empty();
  }
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const Stream.empty();
  final events = StreamController<void>();
  final sync = PortalAccessSync(
      client: client,
      institutionId: identity.$2!,
      onChange: () {
        if (!events.isClosed) events.add(null);
      },);
  ref.onDispose(() {
    sync.dispose();
    unawaited(events.close());
  });
  return events.stream;
});
final portalAccessProvider =
    AsyncNotifierProvider<PortalAccessController, PortalAccess>(
        PortalAccessController.new,);

class PortalAccessController extends AsyncNotifier<PortalAccess> {
  int _generation = 0;
  bool _refreshing = false, _pending = false;
  @override
  Future<PortalAccess> build() {
    _generation++;
    ref.onDispose(() {
      _generation++;
    });
    ref.listen(portalAccessChangesProvider, (_, next) {
      if (next.hasValue) unawaited(refresh());
    });
    return ref.watch(portalAccessLoaderProvider)();
  }

  /// Background refresh: identical permissions publish no state and trigger
  /// no dashboard/repository reload. No timer or loading skeleton is used.
  Future<void> refresh() async {
    if (_refreshing) {
      _pending = true;
      return;
    }
    _refreshing = true;
    final generation = _generation;
    try {
      if (state.isLoading) await future;
      if (generation != _generation) return;
      final updated = await ref.read(portalAccessLoaderProvider)();
      if (generation == _generation &&
          (state.hasError ||
              state.valueOrNull?.fingerprint != updated.fingerprint)) {
        state = AsyncData(updated);
      }
    } catch (error, stack) {
      if (generation == _generation) state = AsyncError(error, stack);
    } finally {
      _refreshing = false;
      if (_pending && generation == _generation) {
        _pending = false;
        unawaited(refresh());
      }
    }
  }
}

// Keep cached access during a refresh, but fail closed if verification fails.
final portalResolvedAccessProvider = Provider<PortalAccess?>((ref) {
  final state = ref.watch(portalAccessProvider);
  return state.hasError ? null : state.valueOrNull;
});
final portalCanProvider = Provider.family<bool, String>((ref, code) {
  final access = ref.watch(portalResolvedAccessProvider);
  return access != null &&
      access.can(code) &&
      (code != 'grades.view' || access.anyGradesVisible);
});
final portalFingerprintProvider = Provider<String?>(
  (ref) => ref.watch(portalResolvedAccessProvider)?.fingerprint,
);
final portalAccessConfigProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  final api = ref.watch(backendApiClientProvider);
  ref.watch(authControllerProvider.select((auth) => auth.user?.id));
  if (api == null) {
    throw StateError('La configuración de accesos requiere conexión.');
  }
  return Map<String, dynamic>.from(
    await api.get('/portal-access/config') as Map,
  );
});

String? portalPermissionForPath(String path) {
  if (path.startsWith('/grades')) return 'grades.view';
  if (path.startsWith('/reports')) return 'reports.view';
  if (path.startsWith('/payments')) return 'payments.view';
  if (path.startsWith('/assignments') || path.startsWith('/exams')) {
    return 'assignments.view';
  }
  if (path.startsWith('/my-attendance') ||
      path.startsWith('/parent/attendance')) {
    return 'attendance.view';
  }
  if (path == '/schedule' || path == '/parent/schedule') return 'schedule.view';
  if (path.startsWith('/announcements') || path == '/calendar') {
    return 'announcements.view';
  }
  if (path.startsWith('/chat/new')) return 'messages.send';
  return null;
}
