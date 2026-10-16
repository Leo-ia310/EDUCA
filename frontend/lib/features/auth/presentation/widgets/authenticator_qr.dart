import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

/// Encodes the otpauth URI locally; no secret is sent to an image service.
class AuthenticatorQr extends StatefulWidget {
  const AuthenticatorQr({super.key, required this.data});
  final String data;
  @override
  State<AuthenticatorQr> createState() => _AuthenticatorQrState();
}

class _AuthenticatorQrState extends State<AuthenticatorQr> {
  late QrImage _image;
  void _encode() {
    _image = QrImage(QrCode.fromData(
        data: widget.data, errorCorrectLevel: QrErrorCorrectLevel.M,),);
  }

  @override
  void initState() {
    super.initState();
    _encode();
  }

  @override
  void didUpdateWidget(AuthenticatorQr oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) _encode();
  }

  @override
  Widget build(BuildContext context) => Semantics(
      label: 'Código QR para app autenticadora',
      image: true,
      child: LayoutBuilder(builder: (context, constraints) {
        final side = math.min(240.0, constraints.maxWidth);
        return Align(
            child: CustomPaint(
                size: Size.square(side), painter: _QrPainter(_image),),);
      },),);
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.image);
  final QrImage image;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final unit =
        size.width / (image.moduleCount + 8); // Four-module quiet zone.
    final ink = Paint()
      ..color = Colors.black
      ..isAntiAlias = false;
    for (var row = 0; row < image.moduleCount; row++) {
      for (var col = 0; col < image.moduleCount; col++) {
        if (image.isDark(row, col)) {
          canvas.drawRect(
              Rect.fromLTWH((col + 4) * unit, (row + 4) * unit, unit, unit),
              ink,);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter oldDelegate) => oldDelegate.image != image;
}
