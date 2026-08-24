/// Entidades del panel de desarrollador (Developer Dashboard).
///
/// Modelan las respuestas de las APIs `/api/developer/*` del backend Node.
/// Todas las respuestas vienen envueltas como `{ ok: true, data }`; aquí solo
/// se modela el `data`.
library;

// Helpers de parseo tolerantes (los valores llegan de JSON).
int devInt(dynamic v, [int fallback = 0]) => v is int
    ? v
    : (v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? fallback);

bool devBool(dynamic v, [bool fallback = false]) =>
    v is bool ? v : (v == 'true' || v == 1 ? true : fallback);

String devStr(dynamic v, [String fallback = '']) => v?.toString() ?? fallback;

DateTime? devDate(dynamic v) =>
    (v == null || v == '') ? null : DateTime.tryParse('$v');

Map<String, dynamic> devMap(dynamic v) =>
    (v as Map?)?.cast<String, dynamic>() ?? const {};

/// Contadores del resumen (`GET /api/developer/summary` → `counts`).
class DevSummaryCounts {
  const DevSummaryCounts({
    required this.institutions,
    required this.users,
    required this.modules,
    required this.pendingApis,
    required this.openTasks,
    required this.featureFlags,
    required this.failingChecks,
  });

  final int institutions;
  final int users;
  final int modules;
  final int pendingApis;
  final int openTasks;
  final int featureFlags;
  final int failingChecks;

  factory DevSummaryCounts.fromMap(Map<String, dynamic> m) => DevSummaryCounts(
        institutions: devInt(m['institutions']),
        users: devInt(m['users']),
        modules: devInt(m['modules']),
        pendingApis: devInt(m['pendingApis']),
        openTasks: devInt(m['openTasks']),
        featureFlags: devInt(m['featureFlags']),
        failingChecks: devInt(m['failingChecks']),
      );
}

/// Tarea técnica del dashboard (`developer_tasks`).
class DevTask {
  const DevTask({
    required this.id,
    required this.title,
    this.moduleKey,
    this.description,
    required this.status,
    this.priority,
    this.owner,
    this.frontendRequired = false,
    this.backendReady = false,
    this.dueAt,
    this.completedAt,
    this.notes,
  });

  final int id;
  final String title;
  final String? moduleKey;
  final String? description;

  /// pending | ready | in_progress | blocked | done | cancelled
  final String status;

  /// low | medium | high | critical
  final String? priority;
  final String? owner;
  final bool frontendRequired;
  final bool backendReady;
  final DateTime? dueAt;
  final DateTime? completedAt;
  final String? notes;

  factory DevTask.fromMap(Map<String, dynamic> m) => DevTask(
        id: devInt(m['id']),
        title: devStr(m['title'], 'Tarea'),
        moduleKey: m['module_key'] as String?,
        description: m['description'] as String?,
        status: devStr(m['status'], 'pending'),
        priority: m['priority'] as String?,
        owner: m['owner'] as String?,
        frontendRequired: devBool(m['frontend_required']),
        backendReady: devBool(m['backend_ready']),
        dueAt: devDate(m['due_at']),
        completedAt: devDate(m['completed_at']),
        notes: m['notes'] as String?,
      );
}

/// Evento de auditoría técnica (`developer_audit_events`).
class DevAuditEvent {
  const DevAuditEvent({
    required this.id,
    this.actorUserId,
    required this.entityTable,
    this.entityId,
    required this.action,
    this.createdAt,
  });

  final int id;
  final int? actorUserId;
  final String entityTable;
  final String? entityId;

  /// create | update | archive | ...
  final String action;
  final DateTime? createdAt;

  factory DevAuditEvent.fromMap(Map<String, dynamic> m) => DevAuditEvent(
        id: devInt(m['id']),
        actorUserId:
            m['actor_user_id'] == null ? null : devInt(m['actor_user_id']),
        entityTable: devStr(m['entity_table']),
        entityId: m['entity_id']?.toString(),
        action: devStr(m['action']),
        createdAt: devDate(m['created_at']),
      );
}

/// Entrada del inventario de APIs (`developer_api_registry`).
///
/// Modela cada endpoint que el backend expone y su estado de conexión con el
/// frontend, para el área "APIs por conectar" del panel.
class DevApi {
  const DevApi({
    required this.id,
    this.moduleKey,
    required this.method,
    required this.path,
    this.action,
    this.summary,
    this.description,
    this.authRequired = true,
    this.requiredRoles = const [],
    required this.backendStatus,
    required this.frontendStatus,
    this.sourceFile,
    this.owner,
    this.priority,
    this.notes,
    this.active = true,
  });

  final int id;
  final String? moduleKey;

  /// GET | POST | PATCH | DELETE | ...
  final String method;
  final String path;
  final String? action;
  final String? summary;
  final String? description;
  final bool authRequired;
  final List<String> requiredRoles;

  /// planned | implemented | blocked | deprecated
  final String backendStatus;

  /// pending | connected | blocked | not_needed
  final String frontendStatus;
  final String? sourceFile;
  final String? owner;

  /// low | medium | high | critical
  final String? priority;
  final String? notes;
  final bool active;

  factory DevApi.fromMap(Map<String, dynamic> m) => DevApi(
        id: devInt(m['id']),
        moduleKey: m['module_key'] as String?,
        method: devStr(m['method'], 'GET').toUpperCase(),
        path: devStr(m['path']),
        action: m['action'] as String?,
        summary: m['summary'] as String?,
        description: m['description'] as String?,
        authRequired: devBool(m['auth_required'], true),
        requiredRoles: ((m['required_roles'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        backendStatus: devStr(m['backend_status'], 'planned'),
        frontendStatus: devStr(m['frontend_status'], 'pending'),
        sourceFile: m['source_file'] as String?,
        owner: m['owner'] as String?,
        priority: m['priority'] as String?,
        notes: m['notes'] as String?,
        active: devBool(m['active'], true),
      );
}

/// Feature flag del panel (`developer_feature_flags`).
class DevFeatureFlag {
  const DevFeatureFlag({
    required this.id,
    required this.flagKey,
    required this.title,
    this.description,
    this.enabled = false,
    this.rolloutPercent,
    this.config = const {},
  });

  final int id;
  final String flagKey;
  final String title;
  final String? description;
  final bool enabled;

  /// 0..100 (porcentaje de despliegue gradual).
  final int? rolloutPercent;
  final Map<String, dynamic> config;

  factory DevFeatureFlag.fromMap(Map<String, dynamic> m) => DevFeatureFlag(
        id: devInt(m['id']),
        flagKey: devStr(m['flag_key']),
        title: devStr(m['title'], 'Flag'),
        description: m['description'] as String?,
        enabled: devBool(m['enabled']),
        rolloutPercent:
            m['rollout_percent'] == null ? null : devInt(m['rollout_percent']),
        config: devMap(m['config']),
      );
}

/// Chequeo de salud del sistema (`developer_system_checks`).
class DevSystemCheck {
  const DevSystemCheck({
    required this.id,
    required this.checkKey,
    required this.title,
    this.description,
    this.checkType,
    this.target,
    this.severity,
    required this.status,
    this.enabled = true,
    this.lastCheckedAt,
  });

  final int id;
  final String checkKey;
  final String title;
  final String? description;

  /// manual | sql | http | script
  final String? checkType;
  final String? target;

  /// low | medium | high | critical
  final String? severity;

  /// unknown | passing | warning | failing | disabled
  final String status;
  final bool enabled;
  final DateTime? lastCheckedAt;

  factory DevSystemCheck.fromMap(Map<String, dynamic> m) => DevSystemCheck(
        id: devInt(m['id']),
        checkKey: devStr(m['check_key']),
        title: devStr(m['title'], 'Check'),
        description: m['description'] as String?,
        checkType: m['check_type'] as String?,
        target: m['target'] as String?,
        severity: m['severity'] as String?,
        status: devStr(m['status'], 'unknown'),
        enabled: devBool(m['enabled'], true),
        lastCheckedAt: devDate(m['last_checked_at']),
      );
}

/// Módulo del dashboard (`developer_dashboard_modules`).
class DevModule {
  const DevModule({
    required this.id,
    required this.moduleKey,
    required this.title,
    this.description,
    this.category,
    this.icon,
    this.frontendRoute,
    this.requiredRoles = const [],
    this.enabled = true,
    this.displayOrder,
  });

  final int id;
  final String moduleKey;
  final String title;
  final String? description;
  final String? category;
  final String? icon;
  final String? frontendRoute;
  final List<String> requiredRoles;
  final bool enabled;
  final int? displayOrder;

  factory DevModule.fromMap(Map<String, dynamic> m) => DevModule(
        id: devInt(m['id']),
        moduleKey: devStr(m['module_key']),
        title: devStr(m['title'], 'Módulo'),
        description: m['description'] as String?,
        category: m['category'] as String?,
        icon: m['icon'] as String?,
        frontendRoute: m['frontend_route'] as String?,
        requiredRoles: ((m['required_roles'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        enabled: devBool(m['enabled'], true),
        displayOrder:
            m['display_order'] == null ? null : devInt(m['display_order']),
      );
}

/// Resumen operativo (`GET /api/developer/summary`).
class DevSummary {
  const DevSummary({
    required this.counts,
    required this.pendingTasks,
    required this.recentAuditEvents,
  });

  final DevSummaryCounts counts;
  final List<DevTask> pendingTasks;
  final List<DevAuditEvent> recentAuditEvents;

  factory DevSummary.fromMap(Map<String, dynamic> m) => DevSummary(
        counts: DevSummaryCounts.fromMap(devMap(m['counts'])),
        pendingTasks: ((m['pendingTasks'] as List?) ?? const [])
            .map((e) => DevTask.fromMap(devMap(e)))
            .toList(),
        recentAuditEvents: ((m['recentAuditEvents'] as List?) ?? const [])
            .map((e) => DevAuditEvent.fromMap(devMap(e)))
            .toList(),
      );
}
