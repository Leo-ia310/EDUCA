import 'originality_report.dart';

/// Una fila del resumen: el estado agregado de una entrega (todos sus archivos).
class OriginalityItem {
  const OriginalityItem({
    required this.submissionId,
    required this.studentId,
    required this.state,
    required this.compared,
    required this.coverage,
    required this.binaryIdentical,
    required this.textIdentical,
    required this.submittedAt,
  });
  factory OriginalityItem.fromJson(Map<String, dynamic> json) =>
      OriginalityItem(
        submissionId: (json['submissionId'] as num).toInt(),
        studentId: (json['studentId'] as num).toInt(),
        state: json['state'] as String,
        compared: json['compared'] as bool,
        coverage: (json['coverage'] as num?)?.toDouble(),
        binaryIdentical: json['binaryIdentical'] as bool? ?? false,
        textIdentical: json['textIdentical'] as bool? ?? false,
        submittedAt: DateTime.tryParse(json['submittedAt'] as String? ?? ''),
      );
  final int submissionId, studentId;
  final String state;
  final bool compared, binaryIdentical, textIdentical;
  final double? coverage;
  final DateTime? submittedAt;

  bool get pending => state == 'queued' || state == 'processing';

  /// Sin porcentaje salvo análisis completado con otra entrega comparable.
  double? get shownCoverage =>
      state == 'completed' && compared ? coverage ?? 0 : null;
  OriginalityBand? get band {
    final c = shownCoverage;
    return c == null ? null : OriginalityBand.of(c);
  }

  OriginalityStatusInfo get status =>
      originalityStatus(state, compared: compared);
}

class OriginalitySummary {
  const OriginalitySummary({
    required this.assignmentId,
    required this.eligible,
    required this.preliminary,
    required this.hasTemplate,
    required this.items,
    required this.notice,
  });
  factory OriginalitySummary.fromJson(Map<String, dynamic> json) =>
      OriginalitySummary(
        assignmentId: (json['assignmentId'] as num).toInt(),
        eligible: (json['eligible'] as num).toInt(),
        preliminary: json['preliminary'] as bool,
        hasTemplate: json['hasTemplate'] as bool? ?? false,
        items: (json['items'] as List)
            .map(
              (e) => OriginalityItem.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList(),
        notice: json['notice'] as String,
      );
  final int assignmentId, eligible;
  final bool preliminary, hasTemplate;
  final List<OriginalityItem> items;
  final String notice;

  OriginalityItem? itemFor(String submissionId) {
    for (final i in items) {
      if ('${i.submissionId}' == submissionId) return i;
    }
    return null;
  }

  int count(String state) => items.where((i) => i.state == state).length;
  int get pendingCount => items.where((i) => i.pending).length;
  int get failedCount => count('failed');

  /// Entregas con un resultado definitivo del motor (aunque sea «sin texto»).
  int get analyzedCount => items.length - pendingCount - failedCount;
  int get withPercentage => items.where((i) => i.shownCoverage != null).length;

  /// Hay trabajo en curso: el resumen se vuelve a consultar con espera creciente.
  bool get working => pendingCount > 0;

  Map<OriginalityBand, int> get bands {
    final out = {for (final b in OriginalityBand.values) b: 0};
    for (final i in items) {
      final b = i.band;
      if (b != null) out[b] = out[b]! + 1;
    }
    return out;
  }

  /// Mayor cobertura entre las entregas con porcentaje (null si no hay).
  OriginalityItem? get top {
    OriginalityItem? best;
    for (final i in items) {
      final c = i.shownCoverage;
      if (c == null) continue;
      if (best == null || c > best.shownCoverage!) best = i;
    }
    return best;
  }
}

class OriginalityTemplate {
  const OriginalityTemplate({
    required this.template,
    required this.updatedAt,
    required this.instructionsLines,
  });
  factory OriginalityTemplate.fromJson(Map<String, dynamic> json) =>
      OriginalityTemplate(
        template: json['template'] as String? ?? '',
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
        instructionsLines: (json['instructionsLines'] as num?)?.toInt() ?? 0,
      );
  final String template;
  final DateTime? updatedAt;

  /// Líneas de la descripción/instrucciones que ya se excluyen automáticamente.
  final int instructionsLines;
}
