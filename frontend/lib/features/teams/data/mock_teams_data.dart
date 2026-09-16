import '../../attendance/data/mock_attendance_data.dart';
import '../../attendance/domain/entities.dart';
import '../domain/team_models.dart';

/// Semilla de equipos de trabajo para el modo demo. Los integrantes se toman
/// del roster de cada clase ([AttendanceMock.roster]).
class TeamsMock {
  TeamsMock._();

  static List<WorkTeam> seed() {
    final r101 = AttendanceMock.roster[101] ?? const <StudentBrief>[];
    final r102 = AttendanceMock.roster[102] ?? const <StudentBrief>[];
    return [
      WorkTeam(
        id: 't1',
        classId: 101,
        name: 'Los Integradores',
        members: r101.take(3).toList(),
        score: 92,
        feedback: 'Excelente reparto de tareas y sustentación clara.',
      ),
      WorkTeam(
        id: 't2',
        classId: 101,
        name: 'Vectores Unidos',
        members: r101.skip(3).take(3).toList(),
      ),
      WorkTeam(
        id: 't3',
        classId: 102,
        name: 'Ángulos Rectos',
        members: r102.take(2).toList(),
        score: 78,
        feedback: 'Buen trabajo; cuiden la limpieza del informe.',
      ),
    ];
  }
}
