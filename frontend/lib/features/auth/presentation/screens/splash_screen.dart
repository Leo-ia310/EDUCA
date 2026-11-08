import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/brand_splash.dart';

/// `true` cuando la animación de marca terminó completa. El router no saca al
/// usuario de `/` antes: así el splash dura lo mismo en el primer arranque que
/// en los siguientes, aunque la sesión ya esté lista de inmediato.
final splashFinishedProvider = StateProvider<bool>((ref) => false);

/// Pantalla de arranque: la animación de marca completa. Luego el router decide
/// a dónde ir: al dashboard del rol si hay sesión activa, o al login si no.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void dispose() {
    restoreSystemBars();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Blanco siempre (aunque la app esté en modo oscuro).
    return Scaffold(
      backgroundColor: Colors.white,
      body: BrandSplash(
        onFinished: () =>
            ref.read(splashFinishedProvider.notifier).state = true,
      ),
    );
  }
}
