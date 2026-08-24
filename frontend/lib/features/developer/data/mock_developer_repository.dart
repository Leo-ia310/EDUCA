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
        DevTask(
          id: 1,
          title: 'Conectar dashboard "Resumen" del desarrollador',
          moduleKey: 'developer',
          status: 'in_progress',
          priority: 'high',
          owner: 'Frontend',
          frontendRequired: true,
          backendReady: true,
        ),
        DevTask(
          id: 2,
          title: 'Pantalla de feature flags',
          moduleKey: 'developer',
          status: 'pending',
          priority: 'medium',
          frontendRequired: true,
          backendReady: true,
        ),
        DevTask(
          id: 3,
          title: 'Inventario de APIs por conectar',
          moduleKey: 'developer',
          status: 'ready',
          priority: 'high',
          frontendRequired: true,
          backendReady: true,
        ),
        DevTask(
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
}
