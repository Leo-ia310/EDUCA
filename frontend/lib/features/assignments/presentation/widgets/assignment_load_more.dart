import 'package:flutter/material.dart';
import '../controllers/assignments_list_controller.dart';

/// Pie de las listas de tareas. Con [auto] (listas perezosas), al llegar al
/// final pide la siguiente página sola; si falla ofrece reintentar. Sin [auto]
/// muestra el botón «Cargar más».
class AssignmentLoadMore extends StatelessWidget {
  const AssignmentLoadMore({
    super.key,
    required this.controller,
    this.auto = false,
  });
  final AssignmentFeedController controller;
  final bool auto;

  @override
  Widget build(BuildContext context) {
    if (!controller.hasMore) return const SizedBox.shrink();
    if (!auto) return _manual();
    if (controller.loadMoreError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            const Text('No se pudieron cargar más tareas.'),
            TextButton.icon(
              onPressed: controller.loadingMore ? null : controller.loadMore,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }
    if (!controller.loadingMore) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (controller.mounted && controller.hasMore) controller.loadMore();
      });
    }
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      ),
    );
  }

  Widget _manual() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          if (controller.loadMoreError != null)
            const Text('No se pudieron cargar más tareas.'),
          TextButton.icon(
            onPressed: controller.loadingMore ? null : controller.loadMore,
            icon: controller.loadingMore
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.expand_more_rounded),
            label: Text(
              controller.loadingMore
                  ? 'Cargando…'
                  : controller.loadMoreError != null
                      ? 'Reintentar'
                      : 'Cargar más',
            ),
          ),
        ],
      ),
    );
  }
}
