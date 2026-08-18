import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../domain/entities.dart';
import '../domain/file_upload_service.dart';

const _uuid = Uuid();

/// Sube archivos al bucket `files` de Supabase Storage. La convención de
/// path es `{institution_id}/{folder}/{uuid}_{nombre}` para que las RLS de
/// Storage puedan aislar por institución.
class SupabaseFileUploadService implements FileUploadService {
  SupabaseFileUploadService({
    required SupabaseClient client,
    required this.institutionId,
    this.bucket = 'files',
  }) : _client = client;

  final SupabaseClient _client;
  final int institutionId;
  final String bucket;

  @override
  Future<AssignmentAttachment> upload({
    required File file,
    required String folder,
  }) async {
    final id = _uuid.v4();
    final filename = p.basename(file.path);
    final path = '$institutionId/$folder/${id}_$filename';

    await _client.storage.from(bucket).upload(
          path,
          file,
          fileOptions: const FileOptions(upsert: false),
        );

    final publicUrl = _client.storage.from(bucket).getPublicUrl(path);
    final size = await file.length();
    return AssignmentAttachment(
      id: id,
      name: filename,
      url: publicUrl,
      sizeBytes: size,
      mimeType: _guessMime(filename),
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
