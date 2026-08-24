import 'entities.dart';

/// Contrato del panel de desarrollador. Crece a medida que se conectan más
/// áreas (modules, apis, tasks, feature-flags, system-checks, instituciones,
/// usuarios, auditoría).
abstract class DeveloperRepository {
  /// `GET /api/developer/summary`
  Future<DevSummary> summary();

  /// `GET /api/developer/apis` — inventario de endpoints y su estado.
  Future<List<DevApi>> apis();

  /// `GET /api/developer/tasks` — tareas técnicas (opcionalmente por estado).
  Future<List<DevTask>> tasks({String? status});

  /// `POST /api/developer/tasks` — crea una tarea (payload en snake_case).
  Future<DevTask> createTask(Map<String, dynamic> payload);

  /// `PATCH /api/developer/tasks/:id` — actualización parcial.
  Future<DevTask> updateTask(int id, Map<String, dynamic> payload);

  /// `DELETE /api/developer/tasks/:id` — archiva (soft-delete).
  Future<void> archiveTask(int id);

  /// `GET /api/developer/feature-flags` — flags (opcionalmente por `enabled`).
  Future<List<DevFeatureFlag>> featureFlags({bool? enabled});

  /// `POST /api/developer/feature-flags` — crea un flag (payload snake_case).
  Future<DevFeatureFlag> createFeatureFlag(Map<String, dynamic> payload);

  /// `PATCH /api/developer/feature-flags/:id` — actualización parcial.
  Future<DevFeatureFlag> updateFeatureFlag(int id, Map<String, dynamic> payload);

  /// `DELETE /api/developer/feature-flags/:id` — archiva (soft-delete).
  Future<void> archiveFeatureFlag(int id);

  /// `GET /api/developer/system-checks` — chequeos (filtros status/severity).
  Future<List<DevSystemCheck>> systemChecks({String? status, String? severity});

  /// `POST /api/developer/system-checks` — crea un check (payload snake_case).
  Future<DevSystemCheck> createSystemCheck(Map<String, dynamic> payload);

  /// `PATCH /api/developer/system-checks/:id` — actualización parcial.
  Future<DevSystemCheck> updateSystemCheck(int id, Map<String, dynamic> payload);

  /// `DELETE /api/developer/system-checks/:id` — archiva (soft-delete).
  Future<void> archiveSystemCheck(int id);

  /// `GET /api/developer/modules` — módulos del dashboard.
  Future<List<DevModule>> modules();

  /// `POST /api/developer/modules` — crea un módulo (payload snake_case).
  Future<DevModule> createModule(Map<String, dynamic> payload);

  /// `PATCH /api/developer/modules/:id` — actualización parcial.
  Future<DevModule> updateModule(int id, Map<String, dynamic> payload);

  /// `DELETE /api/developer/modules/:id` — archiva (soft-delete).
  Future<void> archiveModule(int id);

  /// `GET /api/developer/institutions` — instituciones (solo lectura).
  Future<List<DevInstitution>> institutions();

  /// `GET /api/developer/users` — usuarios con sus roles (solo lectura).
  Future<List<DevUser>> users();

  /// `GET /api/developer/audit-events` — actividad técnica (solo lectura).
  Future<List<DevAuditEvent>> auditEvents();
}
