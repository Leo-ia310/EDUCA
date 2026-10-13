import 'package:educa360/core/theme/app_theme.dart';
import 'package:educa360/features/error/presentation/screens/not_found_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final size in const [Size(360, 640), Size(1280, 800)]) {
    testWidgets('404 se muestra sin overflow en ${size.width.toInt()}px',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const NotFoundScreen(location: '/ruta/que/no/existe'),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Página no encontrada'), findsOneWidget);
      expect(
        find.text('La ruta que buscas no existe o fue movida.'),
        findsOneWidget,
      );
      expect(find.text('/ruta/que/no/existe'), findsOneWidget);
      expect(find.text('Volver a la pantalla anterior'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
