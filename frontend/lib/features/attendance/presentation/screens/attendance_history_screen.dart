import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/subject_palette.dart';
import '../../../../core/widgets/brutal.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../../dashboard/data/mock_dashboard_data.dart' show TeacherClass;
import '../../../dashboard/data/supabase_dashboard_datasource.dart'
    show iconForSubject;
import '../../../dashboard/presentation/widgets/student_chrome.dart';
import '../../../dashboard/providers.dart' show teacherDashboardProvider;
import '../../domain/attendance_sync_service.dart';
import '../../domain/entities.dart';
import '../../providers.dart';

final _historyProvider =
    FutureProvider.autoDispose<List<AttendanceSessionSummary>>(
  (ref) => ref.watch(attendanceRepositoryProvider).sessionsHistory(),
);

/// Historial de los pases de lista tomados en este dispositivo y su estado de
/// envío. La app guarda cada pase primero en el teléfono (así funciona sin
/// internet) y lo envía al servidor cuando hay conexión.
class AttendanceHistoryScreen extends ConsumerWidget {
  const AttendanceHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(_historyProvider);
    final palette = context.palette;
    // Nombre real de cada clase (el historial local solo guarda su id).
    final mine = ref.watch(teacherDashboardProvider).asData?.value.myClasses ??
        const <TeacherClass>[];
    final classes = {for (final c in mine) c.classId: c};

    return StudentDetailScaffold(
      title: 'Historial de Asistencia',
      scrollable: false,
      bottomNav: false,
      bodyPadding: EdgeInsets.zero,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 20, 0),
              child: _Intro(),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 20, 0),
              child: _SyncCard(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
              child: Row(
                children: [
                  Icon(
                    Icons.fact_check_rounded,
                    size: 18,
                    color: palette.accentDeep,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Pases registrados',
                    style: context.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
            Expanded(
              child: history.when(
                loading: () => const SkeletonList(),
                error: (e, _) => const EmptyState(
                  icon: Icons.error_outline_rounded,
                  title: 'No se pudo cargar el historial',
                  subtitle: 'Desliza hacia abajo para intentarlo de nuevo.',
                ),
                data: (list) {
                  if (list.isEmpty) {
                    return const EmptyState(
                      icon: Icons.fact_check_rounded,
                      title: 'Sin pases registrados',
                      subtitle:
                          'Cuando finalices un pase de asistencia, lo verás aquí.',
                    );
                  }
                  return RefreshIndicator(
                    color: palette.accentDeep,
                    onRefresh: () async => ref.invalidate(_historyProvider),
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 20, 32),
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 14),
                      itemBuilder: (_, i) {
                        final summary = list[i];
                        final known = classes[summary.classId];
                        return _SessionTile(
                          summary: summary,
                          subject: known?.name ?? summary.subjectName,
                          group: known?.room ?? summary.groupName,
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Explica para qué sirve esta pantalla.
class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.accentSoft,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 20, color: palette.accentDeep),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Aquí ves los pases de lista que tomaste en este teléfono. Si no '
              'había internet, quedan pendientes y se envían solos cuando '
              'vuelve la conexión.',
              style: context.textTheme.bodySmall?.copyWith(
                color: palette.accentDeep,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Estado del envío al servidor. El botón solo aparece cuando hay algo que
/// enviar (o un error que reintentar) y siempre dice qué pasó al terminar.
class _SyncCard extends ConsumerWidget {
  const _SyncCard();

  /// Los avisos de conflicto ya vienen redactados para el docente.
  static bool _isConflict(String? raw) => raw != null && raw.startsWith('Hay ');

  static String _friendly(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    if (_isConflict(raw)) return raw;
    return 'No se pudo enviar. Revisa tu conexión e inténtalo de nuevo.';
  }

  Future<void> _sendNow(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(attendanceSyncProvider.notifier).processQueue();
    ref.invalidate(_historyProvider);
    final after = ref.read(attendanceSyncProvider);
    final ok = after.pending == 0 && after.lastError == null;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Asistencia enviada: todo está al día.'
                : _friendly(after.lastError).isNotEmpty
                    ? _friendly(after.lastError)
                    : 'Aún quedan marcaciones por enviar.',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(attendanceSyncProvider);
    final palette = context.palette;

    final hasError = status.lastError != null && !status.syncing;
    final conflict = hasError && _isConflict(status.lastError);
    final needsSend = status.pending > 0 || hasError;

    final Color tone;
    final IconData icon;
    final String title;
    String subtitle;
    if (status.syncing) {
      tone = palette.info;
      icon = Icons.cloud_sync_rounded;
      title = 'Enviando…';
      subtitle = 'Un momento, estamos enviando tus marcaciones.';
    } else if (conflict) {
      tone = palette.danger;
      icon = Icons.error_outline_rounded;
      title = 'Hay cambios por revisar';
      subtitle = _friendly(status.lastError);
    } else if (status.pending > 0) {
      // Sin internet o el servidor no respondió: las marcaciones están a salvo
      // en el teléfono y se reintenta solo; no es un error del docente.
      tone = palette.warning;
      icon = Icons.cloud_off_rounded;
      title = 'Asistencia sin enviar';
      subtitle = hasError
          ? 'Sin conexión por ahora. Está guardada en tu teléfono y se enviará sola.'
          : 'Se enviará sola cuando haya conexión.';
    } else if (hasError) {
      tone = palette.danger;
      icon = Icons.error_outline_rounded;
      title = 'No se pudo enviar';
      subtitle = _friendly(status.lastError);
    } else {
      tone = palette.success;
      icon = Icons.cloud_done_rounded;
      title = 'Todo enviado';
      subtitle = 'No hay nada pendiente.';
    }
    if (!status.syncing && status.lastSyncAt != null) {
      subtitle =
          '$subtitle Última sincronización: ${DateFormat('HH:mm').format(status.lastSyncAt!)}.';
    }

    return BrutalBox(
      color: context.paper,
      radius: Radii.lg,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(Radii.sm),
                ),
                child: status.syncing
                    ? Padding(
                        padding: const EdgeInsets.all(11),
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: tone,
                        ),
                      )
                    : Icon(icon, color: tone, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: context.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: context.onPaper,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: context.textTheme.bodySmall?.copyWith(
                        color: palette.textMuted,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (needsSend && !status.syncing) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => _sendNow(context, ref),
              style: FilledButton.styleFrom(
                backgroundColor: context.buttonFill,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 44),
              ),
              icon: const Icon(Icons.cloud_upload_rounded, size: 19),
              label: Text(
                hasError && !conflict ? 'Reintentar envío' : 'Enviar ahora',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.summary,
    required this.subject,
    required this.group,
  });
  final AttendanceSessionSummary summary;
  final String subject;
  final String group;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final s = context.pastel(subjectColor(subject));
    final ink = Brutal.ink(context);
    final icon = iconForSubject(subject);
    final fmt = DateFormat("EEE d MMM", 'es');
    final pending = summary.pendingSync;

    return BrutalBox(
      color: s.surface,
      radius: Radii.lg,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: s.vivid,
                  borderRadius: BorderRadius.circular(Radii.sm),
                  border: Border.all(color: ink, width: Brutal.border),
                ),
                child: Icon(icon, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subject,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.titleMedium?.copyWith(
                        color: s.ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.event_rounded, size: 14, color: s.inkMuted),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            group.isEmpty
                                ? fmt.format(summary.date)
                                : '$group · ${fmt.format(summary.date)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.textTheme.bodySmall
                                ?.copyWith(color: s.inkMuted),
                          ),
                        ),
                      ],
                    ),
                    if (pending > 0) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: palette.warning.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(Radii.pill),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.cloud_off_rounded,
                              size: 13,
                              color: palette.warning,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '$pending sin enviar',
                              style: context.textTheme.labelSmall?.copyWith(
                                color: palette.warning,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _Counter(
                icon: Icons.check_circle_rounded,
                color: palette.success,
                label: 'Presentes',
                value: summary.present,
              ),
              _Counter(
                icon: Icons.cancel_rounded,
                color: palette.danger,
                label: 'Ausentes',
                value: summary.absent,
              ),
              _Counter(
                icon: Icons.schedule_rounded,
                color: palette.warning,
                label: 'Tarde',
                value: summary.late,
              ),
              _Counter(
                icon: Icons.groups_rounded,
                color: palette.info,
                label: 'Total',
                value: summary.totalStudents,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Counter extends StatelessWidget {
  const _Counter({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final Color color;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 4),
              Text(
                '$value',
                style: context.textTheme.titleMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          Text(label, style: context.textTheme.labelSmall),
        ],
      ),
    );
  }
}
