import 'package:flutter/material.dart';

/// Ruta `/`: solo un fondo blanco mientras la sesión se resuelve. La animación de
/// marca la dibuja `BrandSplashOverlay` por encima de toda la app, así al
/// desvanecerse deja ver ya la pantalla de destino (login o panel).
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const Scaffold(backgroundColor: Colors.white);
}
