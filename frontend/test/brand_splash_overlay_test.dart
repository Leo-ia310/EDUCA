import 'package:educa360/features/auth/presentation/widgets/brand_splash.dart';
import 'package:educa360/features/auth/presentation/widgets/brand_splash_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(ValueNotifier<String> path) => MaterialApp(
      home: ValueListenableBuilder<String>(
        valueListenable: path,
        builder: (_, p, __) => BrandSplashOverlay(
          path: p,
          splashPath: '/',
          loginPath: '/login',
          child: const Scaffold(body: TextField(key: Key('email'))),
        ),
      ),
    );

double _opacity(WidgetTester tester) =>
    tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity;

Future<void> _pumpFor(WidgetTester tester, Duration total) async {
  for (var t = Duration.zero;
      t < total;
      t += const Duration(milliseconds: 100)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Sale de la app y vuelve, con la secuencia de estados que Flutter permite
/// (resumed → inactive → hidden → paused y de vuelta).
Future<void> _leaveAndReturn(
  WidgetTester tester, {
  AppLifecycleState away = AppLifecycleState.paused,
}) async {
  const down = [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ];
  final index = down.indexOf(away);
  for (final s in down.sublist(0, index + 1)) {
    tester.binding.handleAppLifecycleStateChanged(s);
  }
  await tester.pump();
  for (final s in down.sublist(0, index).reversed) {
    tester.binding.handleAppLifecycleStateChanged(s);
  }
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pump();
}

void main() {
  testWidgets(
      'al abrir, la animación se desvanece sobre el login (que ya está debajo) y se retira',
      (tester) async {
    final path = ValueNotifier('/login');
    await tester.pumpWidget(_app(path));

    // Tapa la app desde el primer momento (sin ver el formulario de golpe)...
    expect(find.byType(BrandSplash), findsOneWidget);
    expect(_opacity(tester), 1);
    // ...pero el formulario ya está construido debajo.
    expect(find.byKey(const Key('email'), skipOffstage: false), findsOneWidget);

    // En algún momento se está desvaneciendo con la animación todavía en pantalla.
    var vioElDesvanecimiento = false;
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(BrandSplash).evaluate().isNotEmpty &&
          _opacity(tester) == 0) {
        vioElDesvanecimiento = true;
      }
    }
    expect(vioElDesvanecimiento, isTrue);
    expect(find.byType(BrandSplash), findsNothing);
  });

  testWidgets(
      'si la sesión aún no está lista (ruta /), espera y se desvanece al salir de /',
      (tester) async {
    final path = ValueNotifier('/');
    await tester.pumpWidget(_app(path));
    await _pumpFor(tester, const Duration(seconds: 8));
    expect(find.byType(BrandSplash), findsOneWidget);
    expect(_opacity(tester), 1, reason: 'no se retira hasta tener destino');

    path.value = '/login';
    await tester.pump();
    expect(_opacity(tester), 0, reason: 'empieza a desvanecerse');
    await _pumpFor(tester, const Duration(milliseconds: 600));
    expect(find.byType(BrandSplash), findsNothing);
  });

  group('al salir de la app y volver', () {
    Future<ValueNotifier<String>> abierta(
      WidgetTester tester,
      String ruta,
    ) async {
      final path = ValueNotifier(ruta);
      await tester.pumpWidget(_app(path));
      await _pumpFor(tester, const Duration(seconds: 8)); // termina el arranque
      expect(find.byType(BrandSplash), findsNothing);
      return path;
    }

    testWidgets('en el login se repite completa y conserva el formulario',
        (tester) async {
      await abierta(tester, '/login');
      await _leaveAndReturn(tester);
      expect(find.byType(BrandSplash), findsOneWidget);
      expect(_opacity(tester), 1);
      expect(
        find.byKey(const Key('email'), skipOffstage: false),
        findsOneWidget,
      );
      await _pumpFor(tester, const Duration(seconds: 8));
      expect(find.byType(BrandSplash), findsNothing);
    });

    testWidgets('fuera del login no se repite', (tester) async {
      await abierta(tester, '/student/dashboard');
      await _leaveAndReturn(tester);
      expect(find.byType(BrandSplash), findsNothing);
    });

    testWidgets('un aviso del sistema (inactive) no cuenta como salir',
        (tester) async {
      await abierta(tester, '/login');
      await _leaveAndReturn(tester, away: AppLifecycleState.inactive);
      expect(find.byType(BrandSplash), findsNothing);
    });

    testWidgets('se repite cada vez que se sale y se vuelve', (tester) async {
      await abierta(tester, '/login');
      for (var vez = 0; vez < 2; vez++) {
        await _leaveAndReturn(tester, away: AppLifecycleState.hidden);
        expect(
          find.byType(BrandSplash),
          findsOneWidget,
          reason: 'vez ${vez + 1}',
        );
        await _pumpFor(tester, const Duration(seconds: 8));
        expect(find.byType(BrandSplash), findsNothing);
      }
    });
  });
}
