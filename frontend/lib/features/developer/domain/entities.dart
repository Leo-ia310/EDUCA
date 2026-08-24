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
