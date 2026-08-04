// Smoke test de Educa360.
//
// Arrancar toda la app (`Educa360App`) en un test requiere inicializar Hive,
// Supabase y providers, lo que la haría frágil. En su lugar verificamos un
// widget base real de la app (`EduCard`) montado sobre el tema real, lo que
// confirma que la suite de tests compila y que los tokens del tema
// (`context.palette`) se resuelven correctamente.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:educa360/core/theme/app_theme.dart';
import 'package:educa360/core/widgets/edu_card.dart';

void main() {
  testWidgets('EduCard renderiza su contenido sobre el tema de la app',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(
          body: EduCard(child: Text('Educa360')),
        ),
      ),
    );

    expect(find.text('Educa360'), findsOneWidget);
    expect(find.byType(EduCard), findsOneWidget);
  });
}
