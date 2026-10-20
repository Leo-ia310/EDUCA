import 'dart:convert';
import 'package:educa360/features/dashboard/data/supabase_dashboard_datasource.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late SupabaseClient client;
  late http.Client transport;
  late List<Uri> requests;
  setUp(() {
    requests = [];
    transport = MockClient((request) async {
      requests.add(request.url);
      final table = request.url.path.split('/').last;
      dynamic body;
      switch (table) {
        case 'teacher_dashboard_classes':
          body = {
            'classes': [
              {
                'classId': 10,
                'groupId': 20,
                'subjectName': 'Math',
                'groupName': 'Group',
                'isOwner': true,
                'permissions': ['class.view'],
              }
            ],
          };
        case 'dashboard_pending_grading':
          body = 0;
        case 'assignment_counters':
          body = {'pending': 55, 'submitted': 0, 'graded': 0, 'toGrade': 0};
        case 'dashboard_attendance_pct':
          body = 0;
        case 'grades':
          expect(
              request.url.queryParameters['evaluations.class_id'], 'in.(10)',);
          expect(request.url.queryParameters['limit'], '5');
          body = [
            {
              'score': 0,
              'evaluation_id': 2005,
              'created_at': '2026-01-01T00:00:00Z',
              'students': {
                'persons': {'first_name': 'Student', 'last_name': 'Test'},
              },
              'evaluations': {
                'max_score': 100,
                'title': 'Evaluation beyond 1000',
              },
            }
          ];
        case 'classes':
          if (request.url.queryParameters['select']!
              .contains('academic_years')) {
            expect(request.url.queryParameters['academic_years.is_current'],
                'eq.true',);
            expect(request.url.queryParameters['active'], 'eq.true');
          }
          body = [
            {
              'id': 10,
              'subjects': {'name': 'Math'},
              'teachers': {
                'persons': {'first_name': 'Teacher', 'last_name': 'Test'},
              },
            }
          ];
        case 'enrollments':
          body = [
            {
              'group_id': 20,
              'groups': {'name': 'Group'},
              'students': {
                'persons': {'first_name': 'Student', 'last_name': 'Test'},
              },
            }
          ];
        case 'assignments':
        case 'schedules':
          body = [];
        default:
          throw StateError('Unexpected dashboard query $table');
      }
      return http.Response(jsonEncode(body), 200,
          headers: {'content-type': 'application/json'}, request: request,);
    });
    client = SupabaseClient('https://fixture.supabase.co', 'fixture-public',
        httpClient: transport,);
  });
  tearDown(() async {
    await client.dispose();
    transport.close();
  });
  test(
      'teacher dashboard avoids management workspace and the capped evaluation-ID lookup',
      () async {
    final data = await SupabaseDashboardDatasource(client, 10).teacherData(7);
    expect(data.myClasses.single.classId, 10);
    expect(data.recentGrades.single.score, 0);
    expect(data.recentGrades.single.topic, 'Tema: Evaluation beyond 1000');
    expect(requests.any((u) => u.path.endsWith('/collaboration_workspace')),
        isFalse,);
    expect(requests.any((u) => u.path.endsWith('/evaluations')), isFalse);
    expect(requests.where((u) => u.path.endsWith('/grades')).length, 1);
  });
  test(
      'student counter comes from all pending tasks, not the five-card preview',
      () async {
    final data = await SupabaseDashboardDatasource(client, 10)
        .studentData(7, showGrades: false);
    expect(data.tasks, isEmpty);
    expect(data.pendingTasks, 55);
    expect(
        requests.where((u) => u.path.endsWith('/assignment_counters')).length,
        1,);
  });
}
