import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_scaffold.dart';
import '../../../../core/widgets/edu_card.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../../shared/models/app_role.dart';
import '../../data/events_store.dart';
import '../../providers.dart';

/// Lista de anuncios/eventos. El admin puede crear nuevos con el FAB.
class AnnouncementsScreen extends ConsumerWidget {
  const AnnouncementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // En modo conectado muestra los eventos reales (`calendar_events`); en
    // demo o mientras carga, cae al store en memoria.
    final List<SchoolEvent> events =
        ref.watch(upcomingEventsViewProvider).maybeWhen(
      data: (list) => list,
      orElse: () => ref.watch(eventsStoreProvider),
    );
    final role = ref.watch(authControllerProvider).user?.activeRole;
    final isAdmin = role == AppRole.admin ||
        role == AppRole.coordinator ||
        role == AppRole.director;

    return AppScaffold(
      appBar: AppBar(
        title: const Text('Anuncios'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      fab: isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => context.push(Routes.eventNew),
              icon: const Icon(Icons.add),
              label: const Text('Nuevo'),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          if (events.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 60),
              child: EmptyState(
                icon: Icons.campaign_outlined,
                title: 'Sin anuncios',
                subtitle: 'Aún no se han publicado anuncios.',
              ),
            )
          else
            for (final e in events)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _EventCard(event: e),
              ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event});
  final SchoolEvent event;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return EduCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: palette.limeSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(event.icon, color: palette.limeDeep, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  style: context.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  event.description,
                  style: context.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _MetaChip(
                      icon: Icons.calendar_today_rounded,
                      label: DateFormat("d 'de' MMM", 'es').format(event.date),
                    ),
                    _MetaChip(
                      icon: Icons.groups_2_outlined,
                      label: event.audience,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: palette.surfaceAlt,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: palette.textMuted),
          const SizedBox(width: 4),
          Text(
            label,
            style: context.textTheme.labelSmall
                ?.copyWith(color: palette.textMuted),
          ),
        ],
      ),
    );
  }
}
