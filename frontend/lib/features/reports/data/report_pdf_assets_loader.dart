import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:dio/dio.dart';
import 'package:printing/printing.dart';

import '../domain/pdf_style.dart';

const _maxLogoBytes = 2 * 1024 * 1024;

/// Descarga el logo del colegio. Devuelve null si no hay URL, falla la red o
/// la imagen es demasiado grande: el PDF usa entonces el logo de Nivra.
Future<List<int>?> _downloadLogo(String? url) async {
  final uri = Uri.tryParse(url?.trim() ?? '');
  if (uri == null || !uri.hasScheme || !uri.scheme.startsWith('http')) {
    return null;
  }
  try {
    final res = await Dio().getUri<List<int>>(
      uri,
      options: Options(
        responseType: ResponseType.bytes,
        sendTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );
    final bytes = res.data;
    if (res.statusCode != 200 ||
        bytes == null ||
        bytes.isEmpty ||
        bytes.length > _maxLogoBytes) {
      return null;
    }
    return bytes;
  } catch (_) {
    return null;
  }
}

/// Carga la tipografía (Inter, la misma de la app), el logo del colegio y el
/// logo de Nivra de respaldo. Sin red la tipografía queda en la estándar del PDF.
Future<PdfAssets> loadPdfAssets({String? logoUrl}) async {
  final fallback = (await rootBundle.load('assets/icons/nivra_app_icon.png'))
      .buffer
      .asUint8List();
  final school = await _downloadLogo(logoUrl);
  try {
    final regular = await PdfGoogleFonts.interRegular();
    final bold = await PdfGoogleFonts.interBold();
    return PdfAssets(
      regular: regular,
      bold: bold,
      schoolLogo: school == null ? null : Uint8List.fromList(school),
      fallbackLogo: fallback,
    );
  } catch (_) {
    return PdfAssets(
      schoolLogo: school == null ? null : Uint8List.fromList(school),
      fallbackLogo: fallback,
    );
  }
}
