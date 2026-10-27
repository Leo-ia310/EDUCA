import 'package:flutter/services.dart' show rootBundle;
import 'package:printing/printing.dart';

import '../domain/report_pdf_service.dart';

/// Carga la tipografía (Inter, la misma de la app) y el logo para el PDF. Si no
/// hay red, la tipografía queda en la estándar del PDF; el logo siempre viene
/// de los assets.
Future<ReportPdfAssets> loadReportPdfAssets() async {
  final logo = (await rootBundle.load('assets/icons/nivra_app_icon.png'))
      .buffer
      .asUint8List();
  try {
    final regular = await PdfGoogleFonts.interRegular();
    final bold = await PdfGoogleFonts.interBold();
    return ReportPdfAssets(regular: regular, bold: bold, logo: logo);
  } catch (_) {
    return ReportPdfAssets(logo: logo);
  }
}
