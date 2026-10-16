import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import 'package:intl/intl.dart';

import '../../../../core/routing/route_paths.dart';

import '../../../../core/theme/app_theme.dart';

import '../../../../core/theme/subject_palette.dart';

import '../../../../core/widgets/depth_card.dart';

import '../../../../core/widgets/empty_state.dart';

import '../../../../core/widgets/error_state.dart';

import '../../../../core/widgets/skeleton.dart';

import '../../../auth/presentation/auth_controller.dart';

import '../../../../shared/models/app_role.dart';

import '../../../dashboard/presentation/widgets/student_chrome.dart';

import '../../domain/entities.dart';

import '../../providers.dart';

/// Lista de anuncios/eventos. El admin puede crear nuevos con el FAB.

class AnnouncementsScreen extends ConsumerStatefulWidget {
  const AnnouncementsScreen({super.key});

  @override
  ConsumerState<AnnouncementsScreen> createState() =>
      _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends ConsumerState<AnnouncementsScreen>
    with WidgetsBindingObserver {
  Timer? _poll;

  bool _active = true;

  final _retrying = <String>{};

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) { if(mounted) ref.invalidate(announcementsProvider); });

    _poll = Timer.periodic(const Duration(seconds: 2), (_) {
      final saved = ref.read(announcementsProvider);

      final drafts = ref.read(announcementPublisherProvider);

      if (_active &&
          !saved.isLoading &&
          ([...?saved.valueOrNull, ...drafts].any((e) => e.isPublishing) || _poll!.tick % 10 == 0)) {
        ref.invalidate(announcementsProvider);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;

    if (_active) ref.invalidate(announcementsProvider);
  }

  @override
  void dispose() {
    _poll?.cancel();

    WidgetsBinding.instance.removeObserver(this);

    super.dispose();
  }

  Future<void> _retry(SchoolEvent event) async {
    if (event.publicationError != null) {
      ref.read(announcementPublisherProvider.notifier).retry(event);

      return;
    }

    setState(() => _retrying.add(event.id));

    try {
      await ref.read(eventsRepositoryProvider).retryDelivery(event.id);

      ref.invalidate(announcementsProvider);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('No se pudo reintentar el envío. Inténtalo de nuevo.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _retrying.remove(event.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final announcements = ref.watch(announcementsProvider);

    final drafts = ref.watch(announcementPublisherProvider);

    final saved = announcements.valueOrNull ?? <SchoolEvent>[];

    final events = [
      ...drafts.where(
        (draft) => !saved.any(
          (e) =>
              e.id == draft.id ||
              (e.requestId != null && e.requestId == draft.requestId),
        ),
      ),
      ...saved,
    ];

    if (drafts.any(
      (draft) => saved.any(
        (e) =>
            e.id == draft.id ||
            (e.requestId != null && e.requestId == draft.requestId),
      ),
    )) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(announcementPublisherProvider.notifier).reconcile(saved);
        }
      });
    }

    final role = ref.watch(authControllerProvider).user?.activeRole;

    final isAdmin = role == AppRole.admin ||
        role == AppRole.coordinator ||
        role == AppRole.director;

    return StudentDetailScaffold(
      title: 'Anuncios',
      showBack: false,
      onRefresh: () async {
        ref.invalidate(announcementsProvider);

        await ref.read(announcementsProvider.future);
      },
      fab: isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => context.push(Routes.eventNew),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Nuevo'),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final event in events)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _EventCard(
                event: event,
                retrying: _retrying.contains(event.id),
                onRetry: () => _retry(event),
              ),
            ),
          if (announcements.hasError)
            ErrorStateView(
              message:
                  'No se pudieron cargar los anuncios. ${announcements.error}',
              onRetry: () => ref.invalidate(announcementsProvider),
            )
          else if (events.isEmpty && announcements.isLoading)
            const SkeletonList()
          else if (events.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 60),
              child: EmptyState(
                icon: Icons.campaign_outlined,
                title: 'Sin anuncios',
                subtitle: 'Aún no se han publicado anuncios.',
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.event,
    required this.onRetry,
    required this.retrying,
  });

  final VoidCallback onRetry;

  final bool retrying;

  final SchoolEvent event;

  @override
  Widget build(BuildContext context) {
    final s = context.pastel(subjectColor(event.title));

    return DepthCard(
      color: s.surface,
      accent: s.vivid,
      soft: true,
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: s.vivid, shape: BoxShape.circle),
            child: const Icon(
              Icons.campaign_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  style: context.textTheme.titleSmall
                      ?.copyWith(color: s.ink, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  event.description,
                  style:
                      context.textTheme.bodySmall?.copyWith(color: s.inkMuted),
                ),
                const SizedBox(height: 10),
                _DeliveryStatus(event: event),
                if (event.publicationError != null ||
                    (event.delivery?.canRetry ?? false))
                  TextButton.icon(
                    onPressed: retrying ? null : onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(
                      retrying
                          ? 'Reintentando…'
                          : event.publicationError != null
                              ? 'Reintentar publicación'
                              : 'Reintentar envío',
                    ),
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
                      label: _audienceLabel(event.audience),
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
    final ink = context.palette.textMuted;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: context.palette.cardElevated.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: ink.withValues(alpha: 0.62)),
          const SizedBox(width: 4),
          Text(
            label,
            style: context.textTheme.labelSmall
                ?.copyWith(color: ink.withValues(alpha: 0.62)),
          ),
        ],
      ),
    );
  }
}

class _DeliveryStatus extends StatelessWidget {
  const _DeliveryStatus({required this.event});

  final SchoolEvent event;

  @override
  Widget build(BuildContext context) {
    final d = event.delivery;

    final active = event.isPublishing;

    final label = event.publicationError ??
        switch (d?.status) {
          'publishing' => 'Publicando…',
          'queued' => 'Preparando envío…',
          'processing' => d?.phase == 'email'
              ? 'Enviando correos… ${d!.processed}/${d.total}'
              : 'Notificando…',
          'completed_with_errors' =>
            'Publicado con incidencias · ${d!.emailFailed} correos pendientes',
          'failed' => 'Publicado · no se pudo completar el envío',
          _ => 'Publicado',
        };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (active)
              SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: context.palette.accent,
                ),
              )
            else
              Icon(
                event.publicationError != null || (d?.canRetry ?? false)
                    ? Icons.info_outline_rounded
                    : Icons.check_circle_rounded,
                size: 17,
                color: context.palette.accent,
              ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                label,
                style: context.textTheme.labelMedium
                    ?.copyWith(color: context.palette.ink),
              ),
            ),
          ],
        ),
        if (active && d?.status == 'processing') ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: d!.total > 0 ? d.processed / d.total : null,
            color: context.palette.accent,
          ),
        ],
        if (d != null && !active && d.total > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${d.emailed} correos enviados · ${d.emailSkipped} sin envío por preferencias',
              style: context.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

String _audienceLabel(String code) => switch (code) {
      'all' => 'Toda la institución',
      'parents' => 'Padres y tutores',
      'students' => 'Estudiantes',
      'teachers' => 'Docentes',
      'staff' => 'Administración',
      _ => code,
    };
