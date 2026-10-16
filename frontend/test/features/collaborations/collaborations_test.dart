import 'package:educa360/core/network/backend_api_client.dart';
import 'package:educa360/core/theme/app_theme.dart';
import 'package:educa360/features/auth/data/mock_auth_repository.dart';
import 'package:educa360/features/auth/domain/auth_repository.dart';
import 'package:educa360/features/auth/presentation/auth_controller.dart';
import 'package:educa360/features/chat/providers.dart';
import 'package:educa360/features/collaborations/collaborations_screen.dart';
import 'package:educa360/features/collaborations/providers.dart';
import 'package:educa360/features/dashboard/data/mock_dashboard_data.dart';
import 'package:educa360/features/dashboard/presentation/screens/class_detail_screen.dart';
import 'package:educa360/shared/models/app_role.dart';
import 'package:educa360/shared/models/app_user.dart';
import 'package:educa360/shared/models/institution.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _TeacherAuth extends MockAuthRepository {
  @override
  Future<AuthSession?> currentSession() async => const AuthSession(
    institution: Institution(id: 2, code: 'TEST', name: 'Test'),
    user: AppUser(id: '5', institutionId: 2, email: 'teacher@demo.com', fullName: 'Teacher', roles: [AppRole.teacher], activeRole: AppRole.teacher),
  );
}
class _Api implements BackendApiClient {
  final requests = <Map<String, dynamic>>[];
  @override
  Future<dynamic> post(String path, {Map<String, dynamic>? data, Map<String, dynamic>? queryParameters, bool authenticated = true}) async {
    expect(path, '/collaborations'); requests.add(data!); return {};
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
Widget _app(Widget screen, {Map<String, dynamic>? workspace, _Api? api}) => ProviderScope(overrides: [
  authRepositoryProvider.overrideWithValue(_TeacherAuth()),
  totalUnreadProvider.overrideWith((ref) => Stream.value(0)),
  if (workspace != null) collaborationWorkspaceProvider.overrideWith((ref) async => workspace),
  if (api != null) backendApiClientProvider.overrideWithValue(api),
], child: MaterialApp(theme: AppTheme.lightTheme, home: screen),);

void main() {
  test('permission dependencies never imply unrelated write privileges', () {
    final permissions = normalizeClassPermissions(['assignments.grade']);
    expect(permissions, {'class.view','students.view','assignments.review','assignments.grade'});
    expect(permissions.contains('grades.write'), false);
    expect(permissions.contains('attendance.write'), false);
    expect(normalizeClassPermissions([]), {'class.view'});
  });
  testWidgets('read-only collaborative class hides write and management actions', (tester) async {
    await tester.pumpWidget(_app(const ClassDetailScreen(teacherClass: TeacherClass(
      classId: 1, name: 'Matemáticas', room: '10mo', icon: Icons.school_rounded,
      isOwner: false, permissions: {'class.view'},
    ),),),);
    await tester.pumpAndSettle();
    expect(find.text('Clase colaborativa'), findsOneWidget);
    expect(find.text('Tomar asistencia'), findsNothing);
    expect(find.text('Libro de notas'), findsNothing);
    expect(find.text('Ver estudiantes'), findsNothing);
    expect(find.text('Invitar profesor colaborador'), findsNothing);
    expect(find.text('Tareas y exámenes'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('invites a teacher to multiple classes with explicit permissions', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _Api();
    final workspace = <String,dynamic>{
      'classes': [for (var i=1;i<=2;i++) {'classId': i, 'subjectName': 'Materia $i', 'groupName': '10mo', 'isOwner':true}],
      'teachers': [{'userId': 20, 'name': 'Profesor invitado'}], 'invitations': <dynamic>[],
    };
    await tester.pumpWidget(_app(const CollaborationsScreen(), workspace: workspace, api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Invitar profesor')); await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<int>)); await tester.pumpAndSettle();
    await tester.tap(find.text('Profesor invitado').last); await tester.pumpAndSettle();
    for (var i=1;i<=2;i++) { await tester.tap(find.text('Materia $i · 10mo')); await tester.pump(); }
    await tester.ensureVisible(find.text('Calificar tareas')); await tester.tap(find.text('Calificar tareas')); await tester.pump();
    await tester.ensureVisible(find.text('Enviar invitación')); await tester.tap(find.text('Enviar invitación')); await tester.pumpAndSettle();
    expect(api.requests, hasLength(1));
    expect(api.requests.single['classIds'], [1,2]);
    expect(api.requests.single['teacherUserId'], 20);
    expect(api.requests.single['permissions'], containsAll(['assignments.grade','assignments.review','students.view','class.view']));
    expect(api.requests.single['permissions'], isNot(contains('attendance.write')));
    expect(api.requests.single['permissions'], isNot(contains('grades.write')));
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('pending recipient can accept but cannot edit permissions', (tester) async {
    final api = _Api();
    await tester.pumpWidget(_app(const CollaborationsScreen(), api: api, workspace: {
      'classes': <dynamic>[], 'teachers': <dynamic>[], 'invitations': [
        {'id': 7, 'classId':1, 'subjectName':'Matemáticas', 'groupName':'10mo', 'inviterName':'Titular', 'teacherName':'Yo',
          'status':'pending','permissions':['class.view'],'incoming':true,'canManage':false,},
      ],
    },),);
    await tester.pumpAndSettle();
    expect(find.text('Aceptar'), findsOneWidget);
    expect(find.text('Editar permisos'), findsNothing);
    expect(find.text('Revocar acceso'), findsNothing);
    await tester.tap(find.text('Aceptar')); await tester.pumpAndSettle();
    expect(api.requests.single, {'action':'accept','invitationId':7});
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
