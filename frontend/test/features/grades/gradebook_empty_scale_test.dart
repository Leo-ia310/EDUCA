import 'package:educa360/core/theme/app_theme.dart';
import 'package:educa360/features/assignments/providers.dart';
import 'package:educa360/features/attendance/domain/entities.dart';
import 'package:educa360/features/grades/domain/entities.dart';
import 'package:educa360/features/grades/domain/grades_repository.dart';
import 'package:educa360/features/grades/presentation/controllers/gradebook_controller.dart';
import 'package:educa360/features/grades/presentation/screens/teacher_gradebook_screen.dart';
import 'package:educa360/features/grades/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' hide Evaluation;

void main() {
  for (final fails in [false, true]) {
    testWidgets('Term 2 handles ${fails ? 'scale errors' : 'missing scale'}',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            teacherClassesProvider.overrideWith(
              (ref) async => [
                const ClassSessionBrief(
                  classId: 1,
                  groupId: 1,
                  subjectName: 'Math',
                  groupName: 'A',
                  startTime: '08:00',
                  endTime: '09:00',
                  studentCount: 1,
                ),
              ],
            ),
            periodsProvider.overrideWith(
              (ref) async => [
                for (final id in ['1', '2'])
                  AcademicPeriod(
                    id: id,
                    name: 'Term $id',
                    startDate: DateTime(2026),
                    endDate: DateTime(2026, 12),
                    weight: 0.5,
                  ),
              ],
            ),
            gradebookScaleProvider.overrideWith((ref) async {
              if (fails) throw StateError('Database unavailable');
              return null;
            }),
            gradebookProvider.overrideWith(
              (ref, args) async => GradebookMatrix(
                evaluations: [
                  if (args.periodId == '2')
                    Evaluation(
                      id: '1',
                      classId: 1,
                      subjectName: 'Math',
                      periodId: args.periodId,
                      title: 'Exam',
                      date: DateTime(2026),
                      maxScore: 100,
                      weight: 1,
                    ),
                ],
                students: const [],
                grades: const {},
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const TeacherGradebookScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sin evaluaciones'), findsOneWidget);
      await tester.tap(find.text('Term 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Term 2').last);
      await tester.pumpAndSettle();
      expect(find.text('Term 2'), findsOneWidget);
      expect(
        find.text(
          fails
              ? 'No se pudo cargar la escala de calificación. Intenta nuevamente.'
              : 'Sin escala de calificación',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Bad state'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
