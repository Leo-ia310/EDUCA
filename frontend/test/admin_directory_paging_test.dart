import 'package:educa360/core/network/backend_api_client.dart';
import 'package:educa360/core/theme/app_theme.dart';
import 'package:educa360/features/admin/data/admin_backend_repository.dart';
import 'package:educa360/features/admin/presentation/screens/admin_people_screen.dart';
import 'package:educa360/features/admin/presentation/screens/admin_schedules_screen.dart';
import 'package:educa360/features/admin/presentation/widgets/directory_picker.dart';
import 'package:educa360/features/auth/data/mock_auth_repository.dart';
import 'package:educa360/features/auth/domain/auth_repository.dart';
import 'package:educa360/features/auth/presentation/auth_controller.dart';
import 'package:educa360/features/chat/providers.dart';
import 'package:educa360/shared/models/app_role.dart';
import 'package:educa360/shared/models/app_user.dart';
import 'package:educa360/shared/models/institution.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Auth extends MockAuthRepository {
  @override
  Future<AuthSession?> currentSession() async => const AuthSession(
      user: AppUser(
          id: '1',
          institutionId: 10,
          email: 'fixture@test.invalid',
          fullName: 'Fixture',
          roles: [AppRole.admin],
          activeRole: AppRole.admin,
          adminPermissions: ['students.view'],),
      institution: Institution(id: 10, code: 'FIXTURE', name: 'Fixture'),);
}

class _DirectoryApi extends BackendApiClient {
  _DirectoryApi(SupabaseClient client) : super(supabase: client);
  final calls = <({String path, Map<String, dynamic> query})>[];
  bool failSecondOptionPage = true;
  @override
  Future<dynamic> get(String path,
      {Map<String, dynamic>? queryParameters,
      bool authenticated = true,}) async {
    final query = queryParameters ?? {};
    calls.add((path: path, query: query));
    final page = (query['page'] as int?) ?? 1,
        search = query['search'] as String? ?? '';
    if (path == '/schedules') {
      return {
        'schedules': [
          {'id': '$page', 'kind': 'class', 'weekdayId': query['weekdayId'] ?? 1,
            'startTime': '08:00', 'endTime': '09:00', 'subject': 'Materia página $page',
            'groupId': query['groupId'], 'groupName': 'Grupo filtrado',},
        ],
        'pageInfo': {'page': page, 'pageSize': 50, 'total': 100, 'totalPages': 2,
          'hasNextPage': page == 1, 'hasPreviousPage': page > 1,},
      };
    }
    if (path == '/admin/directory/options') {
      if (page == 2 && failSecondOptionPage) {
        failSecondOptionPage = false;
        throw StateError('Fallo temporal');
      }
      return {
        'items': [
          {
            'id': search.isNotEmpty ? '1105' : '$page',
            'label': search.isNotEmpty ? 'Estudiante 1105' : 'Alumno $page',
            'subtitle': null,
            'groupId': null,
            'teacherId': null,
            'room': null,
          }
        ],
        'selected': [
          {'id': '9000', 'label': 'Alumno vinculado'},
        ],
        'pageInfo': {
          'page': page,
          'pageSize': 50,
          'total': 1005,
          'totalPages': 21,
          'hasNextPage': page == 1 && search.isEmpty,
          'hasPreviousPage': page > 1,
        },
      };
    }
    expect(path, '/admin/parents');
    final id = search.isNotEmpty ? '1105' : '$page';
    return {
      'items': [
        {
          'id': id,
          'role': 'parent',
          'active': true,
          'persons': {
            'first_name': search.isNotEmpty ? 'Target' : 'Parent',
            'last_name': id,
            'email': 'parent$id@test.invalid',
            'phone': '',
          },
          'group_id': null,
          'class_ids': [],
          'classes': [],
          'child_ids': ['9000'],
          'children': [
            {'id': '9000', 'name': 'Hijo fuera de página'},
          ],
        }
      ],
      'pageInfo': {
        'page': page,
        'pageSize': 50,
        'total': search.isNotEmpty ? 1 : 1005,
        'totalPages': search.isNotEmpty ? 1 : 21,
        'hasNextPage': search.isEmpty,
        'hasPreviousPage': page > 1,
      },
    };
  }
}

void main() {
  late SupabaseClient client;
  late _DirectoryApi api;
  late AdminBackendRepository repository;
  setUp(() {
    client = SupabaseClient('https://fixture.supabase.co', 'fixture-public');
    api = _DirectoryApi(client);
    repository = AdminBackendRepository(api);
  });
  tearDown(() async {
    await client.dispose();
  });
  Widget app(Widget child) => ProviderScope(overrides: [
        adminBackendRepositoryProvider.overrideWithValue(repository),
        authRepositoryProvider.overrideWithValue(_Auth()),
        totalUnreadProvider.overrideWith((ref) => Stream.value(0)),
      ], child: MaterialApp(theme: AppTheme.lightTheme, home: child),);

  testWidgets('schedule filters reset server pages and keep the searchable group picker alive', (tester) async {
    await tester.pumpWidget(app(const AdminSchedulesScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Materia página 1'), findsOneWidget);
    await tester.tap(find.byTooltip('Página siguiente'));
    await tester.pumpAndSettle();
    expect(find.text('Materia página 2'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '1105');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Estudiante 1105'));
    await tester.pumpAndSettle();
    final requests = api.calls.where((c) => c.path == '/schedules').toList();
    expect(requests.last.query['groupId'], '1105');
    expect(requests.last.query['page'], 1);
    expect(find.widgetWithText(TextField, '1105'), findsOneWidget);
    expect(api.calls.any((c) => c.path == '/admin/directory'), isFalse);
  });

  testWidgets(
      'people screen pages and searches on the server without loading a directory or per-person relations',
      (tester) async {
    await tester.pumpWidget(app(const AdminPeopleScreen(role: AppRole.parent)));
    await tester.pumpAndSettle();
    expect(find.text('Parent 1'), findsOneWidget);
    expect(find.text('Hijo fuera de página'), findsOneWidget);
    expect(api.calls.length, 1);
    await tester.ensureVisible(find.byTooltip('Página siguiente'));
    await tester.tap(find.byTooltip('Página siguiente'));
    await tester.pumpAndSettle();
    expect(find.text('Parent 2'), findsOneWidget);
    expect(api.calls.last.query['page'], 2);
    await tester.ensureVisible(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'Target beyond 1000');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.text('Target 1105'), findsOneWidget);
    expect(api.calls.last.query['search'], 'Target beyond 1000');
    expect(api.calls.last.query['page'], 1);
    expect(api.calls.every((c) => c.path == '/admin/parents'), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'picker retains unseen selections across pages, retries the failed page and searches before loading',
      (tester) async {
    var selected = {'9000'};
    await tester.pumpWidget(app(Scaffold(
        body: SingleChildScrollView(
            child: StatefulBuilder(
                builder: (context, setState) => DirectoryPicker(
                    kind: 'students',
                    selected: selected,
                    multiple: true,
                    onChanged: (values) =>
                        setState(() => selected = values),),),),),),);
    await tester.pumpAndSettle();
    expect(api.calls.length, 1);
    expect(api.calls.single.query['includeIds'], '9000');
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Alumno 1'));
    await tester.pumpAndSettle();
    expect(selected, {'9000', '1'});
    await tester.tap(find.text('Cargar más'));
    await tester.pumpAndSettle();
    expect(find.text('Reintentar'), findsOneWidget);
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(api.calls.last.query['page'], 2);
    expect(find.text('Alumno 2'), findsOneWidget);
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Alumno 2'));
    await tester.pumpAndSettle();
    expect(selected, {'9000', '1', '2'});
    await tester.enterText(find.byType(TextField), 'Estudiante 1105');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(api.calls.last.query['page'], 1);
    expect(api.calls.last.query['search'], 'Estudiante 1105');
    expect(selected, {'9000', '1', '2'});
    expect(find.widgetWithText(CheckboxListTile, 'Estudiante 1105'),
        findsOneWidget,);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
