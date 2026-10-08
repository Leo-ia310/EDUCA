import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/backend_api_client.dart';
import '../../../core/network/paginated_response.dart';
import '../domain/entities.dart';
import '../domain/file_upload_service.dart';

const _uuid = Uuid();

class BackendFileRepository {
  BackendFileRepository(this._api);

  final BackendApiClient _api;

  Future<PaginatedResponse<Map<String, dynamic>>> listFiles({
    int page = 1,
    int pageSize = 50,
  }) async {
    final data = await _api.get(
      '/files',
      queryParameters: {
        'page': page,
        'pageSize': pageSize,
      },
    );
    return PaginatedResponse.fromMap(data, (map) => map);
  }

  Future<Map<String, dynamic>> prepareUpload({
    required String originalName,
    required String mimeType,
    required int sizeBytes,
    required String folder,
  }) async {
    final data = await _api.post(
      '/files/prepare-upload',
      data: {
        'originalName': originalName,
        'mimeType': mimeType,
        'sizeBytes': sizeBytes,
        'folder': folder,
      },
    );
    return (data as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> registerMetadata({
    required String originalName,
    required String storagePath,
    required String mimeType,
    required int sizeBytes,
    String? url,
  }) async {
    final data = await _api.post(
      '/files/metadata',
      data: {
        'originalName': originalName,
        'storagePath': storagePath,
        'mimeType': mimeType,
        'sizeBytes': sizeBytes,
        'url': url,
      },
    );
    final map = (data as Map).cast<String, dynamic>();
    return (map['file'] as Map?)?.cast<String, dynamic>() ?? map;
  }
}

/// Sube archivos usando el backend Node para validar MIME/tamaño, generar la
/// ruta multi-tenant y registrar la metadata institucional.
class SupabaseFileUploadService implements FileUploadService {
  SupabaseFileUploadService({
    required SupabaseClient client,
    required BackendApiClient api,
    required this.institutionId,
    this.bucket = 'files',
  })  : _client = client,
        _files = BackendFileRepository(api);

  final SupabaseClient _client;
  final BackendFileRepository _files;
  final int institutionId;
  final String bucket;

  @override
  Future<AssignmentAttachment> upload({
    required File file,
    required String folder,
  }) async {
    final filename = p.basename(file.path);
    final size = await file.length();
    final mimeType = _guessMime(filename);
    final prepared = await _files.prepareUpload(
      originalName: filename,
      mimeType: mimeType,
      sizeBytes: size,
      folder: folder,
    );
    final storagePath = prepared['storagePath']?.toString() ?? '';
    final signedUpload =
        (prepared['signedUpload'] as Map?)?.cast<String, dynamic>() ?? const {};
    final token = signedUpload['token']?.toString();
    if (storagePath.isEmpty || token == null || token.isEmpty) {
      throw StateError('El backend no devolvió una URL firmada válida.');
    }

    await _client.storage.from(bucket).uploadToSignedUrl(
          storagePath,
          token,
          file,
          FileOptions(contentType: mimeType, upsert: false),
        );

    final publicUrl = _client.storage.from(bucket).getPublicUrl(storagePath);
    final metadata = await _files.registerMetadata(
      originalName: filename,
      storagePath: storagePath,
      mimeType: mimeType,
      sizeBytes: size,
      url: publicUrl,
    );

    return AssignmentAttachment(
      id: metadata['id']?.toString() ?? _uuid.v4(),
      name: metadata['originalName']?.toString() ?? filename,
      url: metadata['url']?.toString() ?? publicUrl,
      sizeBytes: (metadata['sizeBytes'] as num?)?.toInt() ?? size,
      mimeType: metadata['mimeType']?.toString() ?? mimeType,
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
