import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_state.dart';
import '../auth/presentation/auth_controller.dart';
import '../../shared/models/app_role.dart';
import 'providers.dart';

class PortalRestriction extends StatelessWidget {
  const PortalRestriction({
    super.key,
    this.message = 'Esta sección está restringida por tu institución.',
  });
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(20),
        child: EmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Acceso restringido',
          subtitle: message,
        ),
      );
}

class PortalRouteGate extends ConsumerWidget {
  const PortalRouteGate({
    super.key,
    required this.path,
    required this.child,
    required this.onHome,
  });
  final String path;
  final Widget child;
  final VoidCallback onHome;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(authControllerProvider).user?.activeRole;
    final code = portalPermissionForPath(path);
    if (code != null && role == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (code == null || ![AppRole.student, AppRole.parent].contains(role)) {
      return child;
    }
    final state = ref.watch(portalAccessProvider);
    final access = state.hasError ? null : state.valueOrNull;
    if (access == null) {
      return Scaffold(
        body: Center(
          child: state.hasError
              ? ErrorStateView(
                  message: 'No se pudieron verificar tus permisos.',
                  onRetry: () => ref.invalidate(portalAccessProvider),
                )
              : const CircularProgressIndicator(),
        ),
      );
    }
    final allowed =
        access.can(code) && (code != 'grades.view' || access.anyGradesVisible);
    if (allowed) return child;
    return Scaffold(
      appBar: AppBar(title: const Text('Acceso restringido')),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const PortalRestriction(),
          Center(
            child: FilledButton(
              onPressed: onHome,
              child: const Text('Volver al inicio'),
            ),
          ),
        ],
      ),
    );
  }
}
