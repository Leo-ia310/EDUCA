import '../domain/developer_repository.dart';
import '../domain/entities.dart';

/// Datos mock para el panel de desarrollador en modo demo, para que el
/// dashboard sea navegable sin backend.
class MockDeveloperRepository implements DeveloperRepository {
  @override
  Future<DevSummary> summary() async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    final now = DateTime.now();
    return DevSummary(
      counts: const DevSummaryCounts(
        institutions: 1,
        users: 42,
        modules: 6,
        pendingApis: 24,
        openTasks: 7,
        featureFlags: 3,
        failingChecks: 1,
      ),
      pendingTasks: [
        const DevTask(
          id: 1,
          title: 'Conectar dashboard "Resumen" del desarrollador',
          moduleKey: 'developer',
          status: 'in_progress',
          priority: 'high',
          owner: 'Frontend',
          frontendRequired: true,
          backendReady: true,
        ),
        const DevTask(
          id: 2,
          title: 'Pantalla de feature flags',
          moduleKey: 'developer',
          status: 'pending',
          priority: 'medium',
          frontendRequired: true,
          backendReady: true,
        ),
        const DevTask(
          id: 3,
          title: 'Inventario de APIs por conectar',
          moduleKey: 'developer',
          status: 'ready',
          priority: 'high',
          frontendRequired: true,
          backendReady: true,
        ),
        const DevTask(
          id: 4,
          title: 'Revisar índice fallando en system-checks',
          moduleKey: 'infra',
          status: 'blocked',
          priority: 'critical',
        ),
      ],
      recentAuditEvents: [
        DevAuditEvent(
          id: 10,
          entityTable: 'developer_feature_flags',
          entityId: '3',
          action: 'update',
          createdAt: now.subtract(const Duration(minutes: 12)),
        ),
        DevAuditEvent(
          id: 9,
          entityTable: 'developer_tasks',
          entityId: '2',
          action: 'create',
          createdAt: now.subtract(const Duration(hours: 2)),
        ),
        DevAuditEvent(
          id: 8,
          entityTable: 'developer_dashboard_modules',
          entityId: '6',
          action: 'create',
          createdAt: now.subtract(const Duration(hours: 5)),
        ),
      ],
    );
  }

  @override
  Future<List<DevApi>> apis() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return const [
      DevApi(
        id: 1,
        moduleKey: 'assignments',
        method: 'POST',
        path: '/api/business-api',
        action: 'assignments.upsert',
        summary: 'Crear/editar tarea',
        backendStatus: 'implemented',
        frontendStatus: 'connected',
        owner: 'Frontend',
        priority: 'high',
      ),
      DevApi(
        id: 2,
        moduleKey: 'attendance',
        method: 'POST',
        path: '/api/business-api',
        action: 'attendance.upsert',
        summary: 'Registrar asistencia',
        backendStatus: 'implemented',
        frontendStatus: 'connected',
        owner: 'Frontend',
        priority: 'high',
      ),
      DevApi(
        id: 3,
        moduleKey: 'grades',
        method: 'POST',
        path: '/api/business-api',
        action: 'grades.setGrade',
        summary: 'Asignar calificación',
        backendStatus: 'implemented',
        frontendStatus: 'pending',
        owner: 'Frontend',
        priority: 'high',
      ),
      DevApi(
        id: 4,
        moduleKey: 'payments',
        method: 'POST',
        path: '/api/business-api',
        action: 'payments.register',
        summary: 'Registrar pago',
        backendStatus: 'implemented',
        frontendStatus: 'pending',
        owner: 'Frontend',
        priority: 'medium',
      ),
      DevApi(
        id: 5,
        moduleKey: 'chat',
        method: 'POST',
        path: '/api/business-api',
        action: 'chat.sendMessage',
        summary: 'Enviar mensaje de chat',
        backendStatus: 'implemented',
        frontendStatus: 'connected',
        priority: 'medium',
      ),
      DevApi(
        id: 6,
        moduleKey: 'events',
        method: 'POST',
        path: '/api/business-api',
        action: 'events.upsert',
        summary: 'Crear/editar evento',
        backendStatus: 'implemented',
        frontendStatus: 'pending',
        priority: 'medium',
      ),
      DevApi(
        id: 7,
        moduleKey: 'notifications',
        method: 'POST',
        path: '/api/business-api',
        action: 'notifications.markRead',
        summary: 'Marcar notificación leída',
        backendStatus: 'implemented',
        frontendStatus: 'connected',
        priority: 'low',
      ),
      DevApi(
        id: 8,
        moduleKey: 'schedule',
        method: 'GET',
        path: '/api/business-api',
        action: 'schedule.list',
        summary: 'Listar horario',
        backendStatus: 'implemented',
        frontendStatus: 'pending',
        priority: 'medium',
      ),
      DevApi(
        id: 9,
        moduleKey: 'reports',
        method: 'GET',
        path: '/api/reports/overview',
        summary: 'Reporte general',
        backendStatus: 'planned',
        frontendStatus: 'pending',
        priority: 'low',
      ),
      DevApi(
        id: 10,
        moduleKey: 'payments',
        method: 'GET',
        path: '/api/payments/export',
        summary: 'Exportar pagos (CSV)',
        backendStatus: 'blocked',
        frontendStatus: 'blocked',
        priority: 'low',
        notes: 'Depende del proveedor de facturación.',
      ),
      DevApi(
        id: 11,
        moduleKey: 'auth',
        method: 'POST',
        path: '/api/auth/reset-password',
        summary: 'Restablecer contraseña',
        backendStatus: 'implemented',
        frontendStatus: 'not_needed',
        priority: 'low',
        notes: 'Se maneja vía Supabase Auth directo.',
      ),
      DevApi(
        id: 12,
        moduleKey: 'developer',
        method: 'GET',
        path: '/api/developer/summary',
        summary: 'Resumen técnico',
        backendStatus: 'implemented',
        frontendStatus: 'connected',
        owner: 'Frontend',
        priority: 'high',
      ),
    ];
  }

  /// Estado en memoria de las tareas técnicas (persiste durante la sesión demo,
  /// para que el CRUD sea navegable sin backend).
  final List<DevTask> _tasks = [
    DevTask(
      id: 1,
      title: 'Conectar área "APIs por conectar"',
      moduleKey: 'developer',
      status: 'done',
      priority: 'high',
      owner: 'Frontend',
      frontendRequired: true,
      backendReady: true,
      completedAt: DateTime.now().subtract(const Duration(hours: 1)),
    ),
    const DevTask(
      id: 2,
      title: 'Construir área "Tareas técnicas" (CRUD)',
      moduleKey: 'developer',
      status: 'in_progress',
      priority: 'high',
      owner: 'Frontend',
      frontendRequired: true,
      backendReady: true,
    ),
    const DevTask(
      id: 3,
      title: 'Pantalla de feature flags',
      moduleKey: 'developer',
      status: 'ready',
      priority: 'medium',
      frontendRequired: true,
      backendReady: true,
    ),
    const DevTask(
      id: 4,
      title: 'Conectar grades.setGrade en el gradebook',
      moduleKey: 'grades',
      description: 'Reemplazar el mock por la llamada real al backend.',
      status: 'pending',
      priority: 'high',
      frontendRequired: true,
      backendReady: true,
    ),
    const DevTask(
      id: 5,
      title: 'Revisar índice fallando en system-checks',
      moduleKey: 'infra',
      status: 'blocked',
      priority: 'critical',
      notes: 'Bloqueado hasta migración 0015.',
    ),
    const DevTask(
      id: 6,
      title: 'Exportación de pagos a CSV',
      moduleKey: 'payments',
      status: 'cancelled',
      priority: 'low',
    ),
  ];

  int _nextTaskId = 7;

  @override
  Future<List<DevTask>> tasks({String? status}) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final list = status == null
        ? _tasks
        : _tasks.where((t) => t.status == status).toList();
    return List<DevTask>.unmodifiable(list);
  }

  @override
  Future<DevTask> createTask(Map<String, dynamic> payload) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final task = DevTask.fromMap({...payload, 'id': _nextTaskId++});
    _tasks.insert(0, task);
    return task;
  }

  @override
  Future<DevTask> updateTask(int id, Map<String, dynamic> payload) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index < 0) throw StateError('Tarea no encontrada.');
    final current = _tasks[index];
    // Fusiona: los campos ausentes en el payload conservan su valor actual.
    final updated = DevTask(
      id: id,
      title: payload.containsKey('title')
          ? devStr(payload['title'], current.title)
          : current.title,
      moduleKey: payload.containsKey('module_key')
          ? payload['module_key'] as String?
          : current.moduleKey,
      description: payload.containsKey('description')
          ? payload['description'] as String?
          : current.description,
      status: payload.containsKey('status')
          ? devStr(payload['status'], current.status)
          : current.status,
      priority: payload.containsKey('priority')
          ? payload['priority'] as String?
          : current.priority,
      owner: payload.containsKey('owner')
          ? payload['owner'] as String?
          : current.owner,
      frontendRequired: payload.containsKey('frontend_required')
          ? devBool(payload['frontend_required'])
          : current.frontendRequired,
      backendReady: payload.containsKey('backend_ready')
          ? devBool(payload['backend_ready'])
          : current.backendReady,
      dueAt: payload.containsKey('due_at')
          ? devDate(payload['due_at'])
          : current.dueAt,
      completedAt: payload.containsKey('completed_at')
          ? devDate(payload['completed_at'])
          : current.completedAt,
      notes: payload.containsKey('notes')
          ? payload['notes'] as String?
          : current.notes,
    );
    _tasks[index] = updated;
    return updated;
  }

  @override
  Future<void> archiveTask(int id) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    _tasks.removeWhere((t) => t.id == id);
  }

  /// Estado en memoria de los feature flags (persiste durante la sesión demo).
  final List<DevFeatureFlag> _flags = [
    const DevFeatureFlag(
      id: 1,
      flagKey: 'developer_dashboard',
      title: 'Panel de desarrollador',
      description: 'Habilita el panel técnico para administración.',
      enabled: true,
      rolloutPercent: 100,
    ),
    const DevFeatureFlag(
      id: 2,
      flagKey: 'web_push',
      title: 'Notificaciones push web',
      description: 'Envío de push vía VAPID (sin Firebase).',
      enabled: true,
      rolloutPercent: 100,
    ),
    const DevFeatureFlag(
      id: 3,
      flagKey: 'new_gradebook',
      title: 'Nuevo libro de calificaciones',
      description: 'Rediseño del gradebook, en despliegue gradual.',
      enabled: false,
      rolloutPercent: 25,
    ),
  ];

  int _nextFlagId = 4;

  @override
  Future<List<DevFeatureFlag>> featureFlags({bool? enabled}) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final list = enabled == null
        ? _flags
        : _flags.where((f) => f.enabled == enabled).toList();
    return List<DevFeatureFlag>.unmodifiable(list);
  }

  @override
  Future<DevFeatureFlag> createFeatureFlag(Map<String, dynamic> payload) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final flag = DevFeatureFlag.fromMap({...payload, 'id': _nextFlagId++});
    _flags.insert(0, flag);
    return flag;
  }

  @override
  Future<DevFeatureFlag> updateFeatureFlag(
      int id, Map<String, dynamic> payload,) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final index = _flags.indexWhere((f) => f.id == id);
    if (index < 0) throw StateError('Flag no encontrado.');
    final current = _flags[index];
    final updated = DevFeatureFlag(
      id: id,
      flagKey: payload.containsKey('flag_key')
          ? devStr(payload['flag_key'], current.flagKey)
          : current.flagKey,
      title: payload.containsKey('title')
          ? devStr(payload['title'], current.title)
          : current.title,
      description: payload.containsKey('description')
          ? payload['description'] as String?
          : current.description,
      enabled: payload.containsKey('enabled')
          ? devBool(payload['enabled'])
          : current.enabled,
      rolloutPercent: payload.containsKey('rollout_percent')
          ? (payload['rollout_percent'] == null
              ? null
              : devInt(payload['rollout_percent']))
          : current.rolloutPercent,
      config: payload.containsKey('config')
          ? devMap(payload['config'])
          : current.config,
    );
    _flags[index] = updated;
    return updated;
  }

  @override
  Future<void> archiveFeatureFlag(int id) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    _flags.removeWhere((f) => f.id == id);
  }
}
