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
  });
  factory OriginalityDocument.fromJson(Map<String, dynamic> json) =>
      OriginalityDocument(
        name: json['name'] as String,
        state: json['state'] as String,
        preliminary: json['preliminary'] as bool,
        compared: json['compared'] as bool,
        submittedAt: DateTime.parse(json['submittedAt'] as String),
        processedAt: DateTime.tryParse(json['processedAt'] as String? ?? ''),
        match: json['topMatch'] == null
            ? null
            : OriginalityMatch.fromJson(
                Map<String, dynamic>.from(json['topMatch'] as Map),
              ),
      );
  final String name, state;
  final bool preliminary, compared;
  final DateTime submittedAt;
  final DateTime? processedAt;
  final OriginalityMatch? match;
  bool get pending => state == 'queued' || state == 'processing';
  double? get coverage =>
      state == 'completed' && compared ? match?.coverage ?? 0 : null;
  String get label => switch (state) {
        'queued' => 'Pendiente de análisis',
        'processing' => 'Procesando',
        'failed' => 'Error de análisis; la entrega sigue válida',
        'insufficient_text' =>
          'Texto insuficiente (PDF escaneado requiere texto seleccionable)',
        'unsupported_format' => 'Formato no compatible',
        'completed' when !compared => 'Sin comparaciones aún',
        'completed' => 'Completado',
        _ => 'Pendiente',
      };
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
  });
  factory OriginalityMatch.fromJson(Map<String, dynamic> json) {
    List<String> fragments(String key) => (json[key] as List? ?? [])
        .map((e) => (e as Map)['text'] as String)
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
    );
  }
  final double coverage;
  final String sourceName, sourceStudent;
  final DateTime sourceSubmittedAt;
  final bool binaryIdentical, textIdentical;
  final List<String> fragments, sourceFragments;
}
