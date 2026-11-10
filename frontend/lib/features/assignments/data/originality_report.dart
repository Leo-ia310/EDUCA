/// Estado de un análisis de coincidencias, con el texto que ve el docente.
/// Compartido entre el resumen de la actividad y el detalle de una entrega.
enum OriginalityTone { neutral, progress, success, caution, error }

class OriginalityStatusInfo {
  const OriginalityStatusInfo(this.label, this.hint, this.tone);
  final String label;
  final String hint;
  final OriginalityTone tone;
}

OriginalityStatusInfo originalityStatus(
  String state, {
  required bool compared,
}) =>
    switch (state) {
      'queued' => const OriginalityStatusInfo(
          'En cola',
          'Análisis pendiente. Se procesará en breve.',
          OriginalityTone.progress,
        ),
      'processing' => const OriginalityStatusInfo(
          'Procesando',
          'Análisis en proceso.',
          OriginalityTone.progress,
        ),
      'failed' => const OriginalityStatusInfo(
          'Error de análisis',
          'No se pudo analizar. La entrega sigue siendo válida; puedes reintentar.',
          OriginalityTone.error,
        ),
      'insufficient_text' => const OriginalityStatusInfo(
          'Texto insuficiente',
          'No hay texto suficiente para comparar (un PDF escaneado requiere texto seleccionable). No se calcula porcentaje.',
          OriginalityTone.caution,
        ),
      'unsupported_format' => const OriginalityStatusInfo(
          'Formato no compatible',
          'Solo se analizan PDF con texto, DOCX, TXT y el texto escrito en la entrega. No se calcula porcentaje.',
          OriginalityTone.caution,
        ),
      'completed' when !compared => const OriginalityStatusInfo(
          'Sin otras entregas',
          'Aún no hay documentos disponibles para comparar. Esto no equivale a 0 %.',
          OriginalityTone.neutral,
        ),
      'completed' => const OriginalityStatusInfo(
          'Completado',
          'Análisis completado.',
          OriginalityTone.success,
        ),
      _ => const OriginalityStatusInfo(
          'Pendiente',
          'Análisis pendiente.',
          OriginalityTone.progress,
        ),
    };

/// Banda de lectura de la cobertura. Es orientativa y deliberadamente neutra:
/// nunca se presenta como «porcentaje de copia» ni sugiere una sanción.
enum OriginalityBand {
  minimal('Mínima'),
  low('Baja'),
  moderate('Moderada'),
  high('Alta');

  const OriginalityBand(this.label);
  final String label;

  static OriginalityBand of(double coverage) => coverage >= 70
      ? high
      : coverage >= 40
          ? moderate
          : coverage >= 15
              ? low
              : minimal;
}

class OriginalityReport {
  const OriginalityReport({required this.documents, required this.notice});
  factory OriginalityReport.fromJson(Map<String, dynamic> json) =>
      OriginalityReport(
        documents: (json['documents'] as List)
            .map(
              (e) => OriginalityDocument.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList(),
        notice: json['notice'] as String,
      );
  final List<OriginalityDocument> documents;
  final String notice;
  bool get pending =>
      documents.isEmpty || documents.any((d) => d.pending || d.preliminary);

  /// Hay trabajo en curso (no solo reporte preliminar): justifica sondear.
  bool get working => documents.isEmpty || documents.any((d) => d.pending);
}

class OriginalityDocument {
  const OriginalityDocument({
    required this.name,
    required this.state,
    required this.preliminary,
    required this.compared,
    required this.submittedAt,
    required this.processedAt,
    required this.match,
    this.id,
    this.errorCode,
    this.algorithmVersion,
  });
  factory OriginalityDocument.fromJson(Map<String, dynamic> json) =>
      OriginalityDocument(
        id: (json['id'] as num?)?.toInt(),
        name: json['name'] as String,
        state: json['state'] as String,
        preliminary: json['preliminary'] as bool,
        compared: json['compared'] as bool,
        submittedAt: DateTime.parse(json['submittedAt'] as String),
        processedAt: DateTime.tryParse(json['processedAt'] as String? ?? ''),
        errorCode: json['errorCode'] as String?,
        algorithmVersion: json['algorithmVersion'] as String?,
        match: json['topMatch'] == null
            ? null
            : OriginalityMatch.fromJson(
                Map<String, dynamic>.from(json['topMatch'] as Map),
              ),
      );
  final int? id;
  final String name, state;
  final bool preliminary, compared;
  final DateTime submittedAt;
  final DateTime? processedAt;
  final String? errorCode, algorithmVersion;
  final OriginalityMatch? match;
  bool get pending => state == 'queued' || state == 'processing';

  /// Solo hay porcentaje con un análisis completado y otra entrega comparable.
  double? get coverage =>
      state == 'completed' && compared ? match?.coverage ?? 0 : null;
  OriginalityStatusInfo get status =>
      originalityStatus(state, compared: compared);
  String get label => status.label;
}

/// Un tramo coincidente. [start]/[end] son posiciones (caracteres) en el texto
/// normalizado de ese documento. Los tramos de ambos documentos NO están
/// emparejados uno a uno: cada lado lista los suyos.
class OriginalityFragment {
  const OriginalityFragment({
    required this.text,
    this.start = 0,
    this.end = 0,
  });
  factory OriginalityFragment.fromJson(Map<String, dynamic> json) =>
      OriginalityFragment(
        text: json['text'] as String,
        start: (json['start'] as num?)?.toInt() ?? 0,
        end: (json['end'] as num?)?.toInt() ?? 0,
      );
  final String text;
  final int start, end;
}

class OriginalityMatch {
  const OriginalityMatch({
    required this.coverage,
    required this.sourceName,
    required this.sourceStudent,
    required this.sourceSubmittedAt,
    required this.binaryIdentical,
    required this.textIdentical,
    required this.fragments,
    required this.sourceFragments,
    this.hasEvidence = false,
  });
  factory OriginalityMatch.fromJson(Map<String, dynamic> json) {
    List<OriginalityFragment> fragments(String key) =>
        (json[key] as List? ?? [])
            .map(
              (e) => OriginalityFragment.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList();
    return OriginalityMatch(
      coverage: (json['coverage'] as num).toDouble(),
      sourceName: json['sourceName'] as String,
      sourceStudent: json['sourceStudent'] as String,
      sourceSubmittedAt: DateTime.parse(json['sourceSubmittedAt'] as String),
      binaryIdentical: json['binaryIdentical'] as bool,
      textIdentical: json['textIdentical'] as bool,
      fragments: fragments('fragments'),
      sourceFragments: fragments('sourceFragments'),
      // La evidencia llega como null cuando no se pidió (evidence=false).
      hasEvidence: json['fragments'] != null,
    );
  }
  final double coverage;
  final String sourceName, sourceStudent;
  final DateTime sourceSubmittedAt;
  final bool binaryIdentical, textIdentical;
  final List<OriginalityFragment> fragments, sourceFragments;
  final bool hasEvidence;
}
