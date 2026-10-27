import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Marca de la institución que emite el documento: nombre a mostrar y logo
/// (URL del colegio; si falta o no se puede leer se usa el de Nivra).
class PdfBranding {
  const PdfBranding({required this.name, this.logoUrl});

  final String name;
  final String? logoUrl;
}

/// Recursos opcionales del PDF: tipografía de la app (Inter) y logos. Si faltan,
/// el documento se genera igual con la tipografía estándar y sin logo.
class PdfAssets {
  const PdfAssets(
      {this.regular, this.bold, this.schoolLogo, this.fallbackLogo,});

  final pw.Font? regular;
  final pw.Font? bold;

  /// Logo del colegio (PNG/JPG) descargado de su `logo_url`.
  final Uint8List? schoolLogo;

  /// Logo de Nivra, de respaldo cuando el colegio no tiene logo válido.
  final Uint8List? fallbackLogo;

  pw.ThemeData? get theme => regular != null && bold != null
      ? pw.ThemeData.withFont(base: regular!, bold: bold!)
      : null;

  /// Imagen lista para el PDF: el logo del colegio si se puede decodificar; si no, el de Nivra.
  pw.MemoryImage? get logo {
    for (final bytes in [schoolLogo, fallbackLogo]) {
      if (bytes == null) continue;
      try {
        return pw.MemoryImage(bytes);
      } catch (_) {
        continue; // formato no soportado (SVG, WebP…)
      }
    }
    return null;
  }
}

typedef PdfAssetsLoader = Future<PdfAssets?> Function({String? logoUrl});

/// Lenguaje visual de la app llevado al PDF: azul de marca, bordes tinta
/// gruesos, sombra dura con el mismo radio de la tarjeta y píldoras.
abstract final class PdfStyle {
  static const ink = PdfColor.fromInt(0xFF0B1B3A);
  static const accent = PdfColor.fromInt(0xFF2563EB);
  static const accentDeep = PdfColor.fromInt(0xFF1D4ED8);
  static const accentSoft = PdfColor.fromInt(0xFFDCE8FF);
  static const surfaceAlt = PdfColor.fromInt(0xFFEEF4FF);
  static const muted = PdfColor.fromInt(0xFF5B6B8C);
  static const line = PdfColor.fromInt(0xFFDCE6F7);
  static const white = PdfColors.white;
  static const success = PdfColor.fromInt(0xFF15803D);
  static const successSoft = PdfColor.fromInt(0xFFDCFCE7);
  static const danger = PdfColor.fromInt(0xFFB91C1C);
  static const dangerSoft = PdfColor.fromInt(0xFFFEE2E2);
  static const sunSoft = PdfColor.fromInt(0xFFFFF1CC);

  static const border = 1.2;
  static const shadow = 3.0;

  /// Tarjeta con borde tinta y sombra dura abajo a la derecha. La sombra se
  /// dibuja a mano con el mismo radio (`boxShadow` la deja cuadrada).
  static pw.Widget card({
    required pw.Widget child,
    PdfColor fill = white,
    double radius = 12,
    pw.EdgeInsets padding = const pw.EdgeInsets.all(14),
    double shadow = PdfStyle.shadow,
  }) {
    return pw.Padding(
      padding: pw.EdgeInsets.only(right: shadow, bottom: shadow),
      child: pw.CustomPaint(
        painter: shadow == 0
            ? null
            : (canvas, size) {
                canvas
                  ..setFillColor(ink)
                  ..drawRRect(shadow, -shadow, size.x, size.y, radius, radius)
                  ..fillPath();
              },
        child: pw.Container(
          padding: padding,
          decoration: pw.BoxDecoration(
            color: fill,
            border: pw.Border.all(color: ink, width: border),
            borderRadius: pw.BorderRadius.circular(radius),
          ),
          child: child,
        ),
      ),
    );
  }

  static pw.Widget logoBox(pw.MemoryImage? logo, {double size = 40}) {
    return pw.Container(
      width: size,
      height: size,
      decoration: pw.BoxDecoration(
        color: white,
        border: pw.Border.all(color: ink, width: border),
        borderRadius: pw.BorderRadius.circular(10),
      ),
      alignment: pw.Alignment.center,
      child: logo == null
          ? pw.Text(
              'N',
              style: pw.TextStyle(
                color: accent,
                fontSize: size * 0.5,
                fontWeight: pw.FontWeight.bold,
              ),
            )
          : pw.Padding(
              padding: const pw.EdgeInsets.all(3),
              child: pw.Image(logo, fit: pw.BoxFit.contain),
            ),
    );
  }

  static pw.Widget chip(
    String label,
    PdfColor fill,
    PdfColor text, {
    PdfColor? borderColor,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: pw.BoxDecoration(
        color: fill,
        border: pw.Border.all(color: borderColor ?? text, width: 0.9),
        borderRadius: pw.BorderRadius.circular(9),
      ),
      child: pw.Text(
        label,
        style: pw.TextStyle(
          color: text,
          fontSize: 8,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  /// Pie con línea tinta, texto a la izquierda y página a la derecha.
  static pw.Widget footer(String text, {String? pageLabel}) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(height: border, color: ink),
        pw.SizedBox(height: 6),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(text, style: const pw.TextStyle(fontSize: 8, color: muted)),
            if (pageLabel != null)
              pw.Text(
                pageLabel,
                style: const pw.TextStyle(
                  fontSize: 8,
                  color: accentDeep,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
