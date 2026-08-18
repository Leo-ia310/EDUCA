import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/edu_card.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/section_header.dart';
import '../../grades/domain/entities.dart';
import '../../grades/presentation/controllers/grades_controller.dart';
import '../../grades/presentation/widgets/grade_pill.dart';
import '../../grades/providers.dart';
import '../providers.dart';

class ReportCardScreen extends ConsumerStatefulWidget {
  const ReportCardScreen({super.key, required this.studentId});
  final int studentId;

  @override
  ConsumerState<ReportCardScreen> createState() => _ReportCardScreenState();
}

class _ReportCardScreenState extends ConsumerState<ReportCardScreen> {
  String? _periodId; // null = anual

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final periodsAsync = ref.watch(periodsProvider);
    final scaleAsync = ref.watch(defaultScaleProvider);
    final card = ref.watch(reportCardProvider(
      StudentGradesArgs(studentId: widget.studentId, periodId: _periodId),
    ));

    return AppScaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Boletín'),
        actions: [
          card.maybeWhen(
            data: (data) => IconButton(
              icon: const Icon(Icons.picture_as_pdf_outlined),
              tooltip: 'Ver PDF',
              onPressed: () => _openPdf(data),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
          card.maybeWhen(
            data: (data) => IconButton(
              icon: const Icon(Icons.ios_share_outlined),
              tooltip: 'Compartir',
              onPressed: () => _sharePdf(data),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      child: card.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorStateView(message: '$e'),
        data: (data) => scaleAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorStateView(message: '$e'),
          data: (scale) => periodsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorStateView(message: '$e'),
            data: (periods) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _PeriodSelector(
                  periods: periods,
                  selected: _periodId,
                  onChanged: (v) => setState(() => _periodId = v),
                ),
                const SizedBox(height: 16),
                _Header(card: data, scale: scale),
                const SizedBox(height: 16),
                const SectionHeader(title: 'Materias'),
                const SizedBox(height: 8),
                EduCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (final line in data.lines) ...[
                        _SubjectLine(line: line, scale: scale),
                        if (line != data.lines.last)
                          Divider(
                              height: 1,
                              color: Theme.of(context)
                                  .dividerColor
                                  .withValues(alpha: 0.5)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => _openPdf(data),
                  icon: const Icon(Icons.picture_as_pdf_rounded),
                  label: const Text('Ver / Descargar boletín en PDF'),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    'Promedio con escala "${scale.name}"',
                    style: context.textTheme.labelSmall
                        ?.copyWith(color: palette.textMuted),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openPdf(ReportCard card) async {
    final pdfService = ref.read(reportPdfServiceProvider);
    await Printing.layoutPdf(
      onLayout: (_) => pdfService.buildReportCard(card),
      name: 'Boletin_${card.studentName}_${card.periodName}.pdf',
    );
  }

  Future<void> _sharePdf(ReportCard card) async {
    final pdfService = ref.read(reportPdfServiceProvider);
    final bytes = await pdfService.buildReportCard(card);
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'Boletin_${card.studentName}_${card.periodName}.pdf'.replaceAll(' ', '_'),
    );
  }
}

class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({
    required this.periods,
    required this.selected,
    required this.onChanged,
  });

  final List<AcademicPeriod> periods;
  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          ChoiceChip(
            label: const Text('Anual'),
            selected: selected == null,
            onSelected: (_) => onChanged(null),
          ),
          const SizedBox(width: 8),
          for (final p in periods) ...[
            ChoiceChip(
              label: Text(p.name),
              selected: selected == p.id,
              onSelected: (_) => onChanged(p.id),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.card, required this.scale});
  final ReportCard card;
  final GradingScale scale;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final fmt = DateFormat("d MMM y", 'es');
    return EduCard(
      color: palette.cardContrast,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(card.studentName,
                        style: context.textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        )),
                    Text('${card.gradeLevel} · ${card.institutionName}',
                        style: context.textTheme.bodySmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.7))),
                  ],
                ),
              ),
              GradePill(score: card.overallAverage, scale: scale),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _HeaderStat(
                label: 'Periodo',
                value: card.periodName,
              ),
              _HeaderStat(
                label: 'Asistencia',
                value: '${card.attendancePct.toStringAsFixed(1)}%',
              ),
              _HeaderStat(
                label: 'Posición',
                value: '${card.rank}/${card.totalPeers}',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${fmt.format(card.periodStart)} – ${fmt.format(card.periodEnd)}',
            style: context.textTheme.labelSmall
                ?.copyWith(color: Colors.white.withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }
}

class _HeaderStat extends StatelessWidget {
  const _HeaderStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: context.textTheme.labelSmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.55),
                fontWeight: FontWeight.w600,
              )),
          const SizedBox(height: 2),
          Text(value,
              style: context.textTheme.titleSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              )),
        ],
      ),
    );
  }
}

class _SubjectLine extends StatelessWidget {
  const _SubjectLine({required this.line, required this.scale});
  final ReportCardLine line;
  final GradingScale scale;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: palette.limeSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.menu_book_rounded,
                color: palette.limeDeep, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.subjectName,
                    style: context.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800)),
                Text(line.teacherName, style: context.textTheme.bodySmall),
              ],
            ),
          ),
          GradePill(score: line.finalScore, scale: scale),
        ],
      ),
    );
  }
}
