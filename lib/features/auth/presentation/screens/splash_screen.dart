import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../auth_controller.dart';

/// Pantalla de arranque. Muestra el branding un instante y luego decide a
/// dónde ir: si ya hay sesión activa va al dashboard del rol; si no, al
/// ingreso de código de institución.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      if (!mounted) return;
      final auth = ref.read(authControllerProvider);
      if (auth.isAuthenticated) {
        context.go(auth.user!.activeRole.dashboardRoute);
      } else {
        context.go(Routes.institutionCode);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: context.palette.limeDeep,
                borderRadius: BorderRadius.circular(24),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.school_rounded,
                  color: Color(0xFF1E2218), size: 40),
            ),
            const SizedBox(height: 16),
            Text('Educa360',
                style: context.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 24),
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
          ],
        ),
      ),
    );
  }
}
