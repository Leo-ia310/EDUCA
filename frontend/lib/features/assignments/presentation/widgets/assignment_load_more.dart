import 'package:flutter/material.dart';
import '../controllers/assignments_list_controller.dart';

class AssignmentLoadMore extends StatelessWidget {
  const AssignmentLoadMore({super.key, required this.controller});
  final AssignmentFeedController controller;

  @override
  Widget build(BuildContext context) {
    if (!controller.hasMore) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(children: [
        if (controller.loadMoreError != null)
          const Text('No se pudieron cargar más tareas.'),
        TextButton.icon(
          onPressed: controller.loadingMore ? null : controller.loadMore,
          icon: controller.loadingMore
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),)
              : const Icon(Icons.expand_more_rounded),
          label: Text(controller.loadingMore
              ? 'Cargando…'
              : controller.loadMoreError != null
                  ? 'Reintentar'
                  : 'Cargar más',),
        ),
      ],),
    );
  }
}
