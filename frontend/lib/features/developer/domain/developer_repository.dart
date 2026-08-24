import 'entities.dart';

/// Contrato del panel de desarrollador. Crece a medida que se conectan más
/// áreas (modules, apis, tasks, feature-flags, system-checks, instituciones,
/// usuarios, auditoría).
abstract class DeveloperRepository {
  /// `GET /api/developer/summary`
  Future<DevSummary> summary();

  /// `GET /api/developer/apis` — inventario de endpoints y su estado.
  Future<List<DevApi>> apis();
}
