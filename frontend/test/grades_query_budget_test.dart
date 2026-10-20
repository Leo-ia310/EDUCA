import 'dart:convert';
import 'package:educa360/core/network/backend_api_client.dart';
import 'package:educa360/features/grades/data/supabase_grades_repository.dart';
import 'package:educa360/features/grades/domain/entities.dart';
import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const scale = GradingScale(
    id: '1',
    name: '100',
    type: ScaleType.numeric,
    minValue: 0,
    maxValue: 100,
    passValue: 60,
    decimals: 2,
    ranges: [],);

class _FixtureApi extends BackendApiClient {
  _FixtureApi(SupabaseClient client) : super(supabase: client);
  int calls = 0;
  @override
  Future<dynamic> get(String path,
      {Map<String, dynamic>? queryParameters,
      bool authenticated = true,}) async {
    calls++;
    expect(path, '/grades/gradebook');
    return {
      'evaluations': List.generate(
          30,
          (i) => {
                'id': '${i + 1}',
                'title': 'Eval',
                'date': '2026-05-01',
                'maxScore': 100,
                'weight': 1,
                'kind': 'homework',
                'subjectName': 'Math',
              },),
      'students': List.generate(
          40, (i) => {'studentId': '${i + 1}', 'name': 'Student ${i + 1}'},),
      'grades': {
        for (var s = 1; s <= 40; s++)
          '$s': {
            for (var e = 1; e <= 30; e++)
              '$e': s == 2 && e == 1
                  ? null
                  : s == 1 && e == 1
                      ? 0
                      : 80,
          },
      },
    };
  }
}

class _DatabaseFixture {
  final requests = <Uri>[];
  late final evaluations = List.generate(
      1440,
      (i) => <String, dynamic>{
            'id': i + 1,
            'class_id': i % 12 + 1,
            'academic_period_id': (i ~/ 12) % 4 + 1,
            'title': 'Eval ${i + 1}',
            'date': '2026-05-01',
            'max_score': 100,
            'weight': 1,
            'classes': {
              'subjects': {'name': 'Subject ${i % 12 + 1}'},
            },
            'catalog_evaluation_types': {'code': 'TAR'},
          },);
  late final grades = List.generate(
      evaluations.length,
      (i) => <String, dynamic>{
            'id': i + 1,
            'evaluation_id': i + 1,
            'student_id': 7,
            'score': i == 0
                ? 0
                : i == 1439
                    ? null
                    : 80,
            'notes': null,
            'evaluations': {
              'academic_period_id': evaluations[i]['academic_period_id'],
            },
          },);
  Future<http.Response> handle(http.Request request) async {
    requests.add(request.url);
    final table = request.url.path.split('/').last,
        query = request.url.queryParameters;
    if (table == 'student_report_context') {
      return http.Response(
          jsonEncode({
            'studentName': 'Student',
            'institutionName': 'School',
            'gradeLevel': 'A',
            'yearStart': '2026-01-01',
            'yearEnd': '2026-12-31',
            'attendancePct': null,
            'rank': null,
            'totalPeers': null,
          }),
          200,
          headers: {'content-type': 'application/json'},
          request: request,);
    }
    expect(query['institution_id'], 'eq.10');
    var rows = switch (table) {
      'academic_years' => <Map<String, dynamic>>[
          {'id': 1},
        ],
      'academic_periods' => List.generate(
          4,
          (i) => <String, dynamic>{
                'id': i + 1,
                'name': 'P${i + 1}',
                'weight': 25,
                'start_date': '2026-01-01',
                'end_date': '2026-12-31',
                'closed': false,
              },),
      'enrollments' => <Map<String, dynamic>>[
          {'group_id': 5, 'academic_year_id': 1},
        ],
      'classes' => List.generate(
          12,
          (i) => <String, dynamic>{
                'id': i + 1,
                'subjects': {'name': 'Subject ${i + 1}'},
                'teachers': {
                  'persons': {'first_name': 'Teacher', 'last_name': 'Test'},
                },
              },),
      'evaluations' => evaluations,
      'grades' => grades,
      _ => throw StateError('Unexpected table $table'),
    };
    if (table == 'grades') {
      expect(query['score'], 'not.is.null');
      rows = rows.where((row) => row['score'] != null).toList();
      final period = query['evaluations.academic_period_id'];
      if (period != null) {
        rows = rows
            .where((row) =>
                (row['evaluations'] as Map)['academic_period_id'].toString() ==
                period.substring(3),)
            .toList();
      }
    }
    final from = int.tryParse(query['offset'] ?? '') ?? 0,
        limit = int.tryParse(query['limit'] ?? '') ?? rows.length;
    final page = rows.skip(from).take(limit).toList();
    return http.Response(jsonEncode(page), 200,
        headers: {'content-type': 'application/json'}, request: request,);
  }
}

void main() {
  late _DatabaseFixture database;
  late http.Client httpClient;
  late SupabaseClient client;
  late _FixtureApi api;
  late SupabaseGradesRepository repository;
  setUp(() {
    database = _DatabaseFixture();
    httpClient = MockClient(database.handle);
    client = SupabaseClient('https://fixture.supabase.co', 'public-fixture',
        httpClient: httpClient,);
    api = _FixtureApi(client);
    repository =
        SupabaseGradesRepository(client: client, api: api, institutionId: 10);
  });
  tearDown(() async {
    await client.dispose();
    httpClient.close();
  });

  test(
      '12 subjects x 4 periods read 1440 evaluations by pages, not one query per pair',
      () async {
    final result =
        await repository.performanceForStudent(studentId: 7, scale: scale);
    expect(result.length, 12);
    expect(result.first.evaluationCount, 120);
    expect(result.first.finalScore, 79.33);
    expect(result.last.evaluationCount, 119);
    expect(result.last.finalScore, 80);
    expect(
        database.requests
            .where((uri) => uri.path.endsWith('/evaluations'))
            .length,
        4,);
    expect(
        database.requests.where((uri) => uri.path.endsWith('/grades')).length,
        4,);
    expect(database.requests.length, lessThanOrEqualTo(15));
  });

  test(
      'period filtering is sent to SQL and ungraded NULL scores are not zero grades',
      () async {
    final rows = await repository.gradesFor(studentId: 7, periodId: '2');
    expect(rows.length, 360);
    expect(
        database.requests.every((uri) =>
            uri.queryParameters['evaluations.academic_period_id'] == 'eq.2',),
        isTrue,);
  });

  test(
      'gradebook is one backend request and retains all 1200 cells, zeroes and missing grades',
      () async {
    final matrix = await repository.gradebook(classId: 1, periodId: '1');
    expect(api.calls, 1);
    expect(database.requests, isEmpty);
    expect(matrix.grades.length, 40);
    expect(matrix.grades.values.fold<int>(0, (n, row) => n + row.length), 1200);
    expect(matrix.grades[1]?['1'], 0);
    expect(matrix.grades[2]?['1'], isNull);
    expect(matrix.grades[40]?['30'], 80);
  });

  test(
      'report does not invent first place or perfect attendance and reuses loaded periods',
      () async {
    final card =
        await repository.reportCardForStudent(studentId: 7, scale: scale);
    expect(card.rank, isNull);
    expect(card.totalPeers, isNull);
    expect(card.attendancePct, isNull);
    expect(card.lines.length, 12);
    expect(card.hasGrades, isTrue);
    expect(
        database.requests
            .where((uri) => uri.path.endsWith('/academic_periods'))
            .length,
        1,);
  });
}
