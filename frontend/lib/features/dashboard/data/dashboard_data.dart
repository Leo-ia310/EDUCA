import '../domain/dashboard_models.dart';
import 'mock_dashboard_data.dart';

/// Datos agregados del dashboard del estudiante. Se llena desde Supabase en
/// modo conectado (ver `SupabaseDashboardDatasource`) o desde el mock en demo.
class StudentDashboardData {
  const StudentDashboardData({
    required this.pendingTasks,
    required this.todaySchedule,
    required this.subjects,
    required this.tasks,
    required this.grades,
    required this.averageScore,
    required this.classmates,
    required this.classmatesExtra,
  });

  final int pendingTasks;
  final List<ScheduleSlot> todaySchedule;
  final List<SubjectProgress> subjects;
  final List<TaskBrief> tasks;
  final List<GradeBrief> grades;
  final double averageScore;
  final List<String> classmates;
  final int classmatesExtra;

  /// Datos de demo (mock), para cuando no hay backend.
  factory StudentDashboardData.mock() => const StudentDashboardData(
        pendingTasks: StudentMockData.pendingTasks,
        todaySchedule: StudentMockData.todaySchedule,
        subjects: StudentMockData.subjects,
        tasks: StudentMockData.tasks,
        grades: StudentMockData.grades,
        averageScore: StudentMockData.averageScore,
        classmates: StudentMockData.classmates,
        classmatesExtra: StudentMockData.classmatesExtra,
      );

  /// Estudiante conectado pero sin datos aún (evita pantalla vacía rota).
  factory StudentDashboardData.empty() => const StudentDashboardData(
        pendingTasks: 0,
        todaySchedule: [],
        subjects: [],
        tasks: [],
        grades: [],
        averageScore: 0,
        classmates: [],
        classmatesExtra: 0,
      );
}

/// Datos agregados del dashboard del docente.
class TeacherDashboardData {
  const TeacherDashboardData({
    required this.quickAttendance,
    required this.myClasses,
    required this.upcomingAssignments,
    required this.recentGrades,
    required this.pendingClasses,
    required this.pendingGrading,
  });

  final List<AttendanceLine> quickAttendance;
  final List<TeacherClass> myClasses;
  final List<UpcomingAssignment> upcomingAssignments;
  final List<RecentGrade> recentGrades;
  final int pendingClasses;
  final int pendingGrading;

  factory TeacherDashboardData.mock() => const TeacherDashboardData(
        quickAttendance: TeacherMockData.quickAttendance,
        myClasses: TeacherMockData.myClasses,
        upcomingAssignments: TeacherMockData.upcomingAssignments,
        recentGrades: TeacherMockData.recentGrades,
        pendingClasses: TeacherMockData.pendingClasses,
        pendingGrading: TeacherMockData.pendingGrading,
      );

  factory TeacherDashboardData.empty() => const TeacherDashboardData(
        quickAttendance: [],
        myClasses: [],
        upcomingAssignments: [],
        recentGrades: [],
        pendingClasses: 0,
        pendingGrading: 0,
      );
}

/// Datos agregados del dashboard del padre/madre (para el hijo seleccionado).
class ParentDashboardData {
  const ParentDashboardData({
    required this.children,
    required this.attendancePercent,
    required this.monthEvents,
    required this.newNotices,
    required this.subjects,
    required this.recentActivity,
  });

  final List<ChildBrief> children;
  final double attendancePercent;
  final int monthEvents;
  final int newNotices;
  final List<ParentSubject> subjects;
  final List<ParentActivity> recentActivity;

  factory ParentDashboardData.mock() => const ParentDashboardData(
        children: ParentMockData.children,
        attendancePercent: ParentMockData.attendancePercent,
        monthEvents: ParentMockData.monthEvents,
        newNotices: ParentMockData.newNotices,
        subjects: ParentMockData.subjects,
        recentActivity: ParentMockData.recentActivity,
      );

  factory ParentDashboardData.empty() => const ParentDashboardData(
        children: [ChildBrief('Sin hijos', selected: true)],
        attendancePercent: 0,
        monthEvents: 0,
        newNotices: 0,
        subjects: [],
        recentActivity: [],
      );
}

/// Datos agregados del dashboard del administrador (a nivel institución).
class AdminDashboardData {
  const AdminDashboardData({
    required this.attendancePct,
    required this.institutionalAvg,
    required this.totalStudents,
    required this.activeTeachers,
    required this.upcomingEvents,
    required this.systemAlerts,
    required this.announcements,
    required this.teachers,
  });

  final double attendancePct;
  final double institutionalAvg;
  final int totalStudents;
  final int activeTeachers;
  final int upcomingEvents;
  final int systemAlerts;
  final List<Announcement> announcements;
  final List<AdminTeacher> teachers;

  factory AdminDashboardData.mock() => const AdminDashboardData(
        attendancePct: AdminMockData.attendancePct,
        institutionalAvg: AdminMockData.institutionalAvg,
        totalStudents: AdminMockData.totalStudents,
        activeTeachers: AdminMockData.activeTeachers,
        upcomingEvents: AdminMockData.upcomingEvents,
        systemAlerts: AdminMockData.systemAlerts,
        announcements: AdminMockData.announcements,
        teachers: AdminMockData.teachers,
      );
}
