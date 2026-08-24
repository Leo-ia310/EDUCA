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
}
