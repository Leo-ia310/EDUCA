import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../attendance/data/mock_attendance_data.dart';
import '../../../attendance/domain/entities.dart';
import '../../data/mock_teams_data.dart';
import '../../domain/team_models.dart';

/// Estado en memoria de los equipos de trabajo (persiste durante la sesión en
/// modo demo, no hay backend detrás).
class TeamsController extends StateNotifier<List<WorkTeam>> {
  TeamsController() : super(TeamsMock.seed());

  int _seq = 100;
  String _nextId() => 't${_seq++}';

  WorkTeam create({required int classId, required String name}) {
    final team = WorkTeam(
      id: _nextId(),
      classId: classId,
      name: name.trim().isEmpty ? 'Equipo nuevo' : name.trim(),
      members: const [],
    );
    state = [...state, team];
    return team;
  }

  void rename(String teamId, String name) =>
      _update(teamId, (t) => t.copyWith(name: name.trim()));

  void addMember(String teamId, StudentBrief student) => _update(
        teamId,
        (t) => t.members.any((m) => m.id == student.id)
            ? t
            : t.copyWith(members: [...t.members, student]),
      );

  void removeMember(String teamId, int studentId) => _update(
        teamId,
        (t) => t.copyWith(
          members: t.members.where((m) => m.id != studentId).toList(),
        ),
      );

  void grade(String teamId, {required double score, String? feedback}) =>
      _update(teamId, (t) => t.copyWith(score: score, feedback: feedback));

  void delete(String teamId) =>
      state = state.where((t) => t.id != teamId).toList();

  void _update(String teamId, WorkTeam Function(WorkTeam) fn) {
    state = [
      for (final t in state) if (t.id == teamId) fn(t) else t,
    ];
  }
}

final teamsControllerProvider =
    StateNotifierProvider<TeamsController, List<WorkTeam>>(
  (ref) => TeamsController(),
);

/// Equipos de una clase.
final teamsForClassProvider =
    Provider.family<List<WorkTeam>, int>((ref, classId) {
  return ref
      .watch(teamsControllerProvider)
      .where((t) => t.classId == classId)
      .toList();
});

/// Un equipo por id (para la pantalla de detalle; se actualiza al editar).
final teamByIdProvider =
    Provider.family<WorkTeam?, String>((ref, teamId) {
  for (final t in ref.watch(teamsControllerProvider)) {
    if (t.id == teamId) return t;
  }
  return null;
});

/// Estudiantes de la clase que aún no están en ningún equipo de esa clase.
final availableStudentsProvider =
    Provider.family<List<StudentBrief>, int>((ref, classId) {
  final roster = AttendanceMock.roster[classId] ?? const <StudentBrief>[];
  final taken = <int>{
    for (final t in ref.watch(teamsForClassProvider(classId)))
      for (final m in t.members) m.id,
  };
  return roster.where((s) => !taken.contains(s.id)).toList();
});
