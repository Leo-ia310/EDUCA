import 'dart:io';

import '../domain/entities.dart';

/// Servicio para subir archivos a un backend (Supabase Storage en producción,
/// no-op en demo). Los repositorios y controllers dependen de esta
/// abstracción para no acoplarse a Supabase directamente.
abstract class FileUploadService {
  /// Sube un archivo y devuelve la metadata para persistir junto a la
  /// tarea/entrega.
  Future<AssignmentAttachment> upload({
    required File file,
    required String folder,
  });
}

/// Implementación de demo: NO sube nada, devuelve la ruta local con
/// esquema `demo://`. Útil para validar flujos sin Supabase configurado.
class DemoFileUploadService implements FileUploadService {
  const DemoFileUploadService();

  @override
  Future<AssignmentAttachment> upload({
    required File file,
    required String folder,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    final stat = await file.length();
    final name = file.path.split(Platform.pathSeparator).last;
    return AssignmentAttachment(
      id: 'demo-${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      url: 'demo://$folder/$name',
      sizeBytes: stat,
      mimeType: _guessMime(name),
    );
  }

  String _guessMime(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    return 'application/octet-stream';
  }
}
