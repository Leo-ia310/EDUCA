import 'package:educa360/features/auth/presentation/widgets/brand_splash.dart';
import 'package:educa360/features/auth/presentation/widgets/brand_splash_replay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(String path) => MaterialApp(
      home: BrandSplashReplay(
        path: path,
        loginPath: '/login',
        child: const Scaffold(body: TextField(key: Key('email'))),
      ),
    );

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
      'en el login, salir de la app y volver repite la animación y la deja terminar',
      (tester) async {
    await tester.pumpWidget(_app('/login'));
    expect(find.byType(BrandSplash), findsNothing);

    await _leaveAndReturn(tester);
    expect(find.byType(BrandSplash), findsOneWidget);

    // Lo escrito en el formulario no se pierde: el login sigue debajo, no se recrea.
    expect(find.byKey(const Key('email')), findsOneWidget);

    // Termina tras una vuelta (3 s + decodificación) y se retira con su fundido.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.byType(BrandSplash), findsNothing);
  });

  testWidgets('fuera del login no se repite', (tester) async {
    await tester.pumpWidget(_app('/student/dashboard'));
    await _leaveAndReturn(tester);
    expect(find.byType(BrandSplash), findsNothing);
  });

  testWidgets('un aviso del sistema (inactive) no cuenta como salir de la app',
      (tester) async {
    await tester.pumpWidget(_app('/login'));
    await _leaveAndReturn(tester, away: AppLifecycleState.inactive);
    expect(find.byType(BrandSplash), findsNothing);
  });

  testWidgets('cada vez que se sale y se vuelve al login se repite',
      (tester) async {
    await tester.pumpWidget(_app('/login'));
    for (var vez = 0; vez < 2; vez++) {
      await _leaveAndReturn(tester, away: AppLifecycleState.hidden);
      expect(
        find.byType(BrandSplash),
        findsOneWidget,
        reason: 'vez ${vez + 1}',
      );
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(find.byType(BrandSplash), findsNothing);
    }
  });
}
