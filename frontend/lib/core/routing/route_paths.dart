class Routes {
  Routes._();

  static const splash = '/';
  static const institutionCode = '/institution-code';
  static const login = '/login';
  static const forgotPassword = '/forgot-password';

  static const studentDashboard = '/student/dashboard';
  static const teacherDashboard = '/teacher/dashboard';
  static const parentDashboard = '/parent/dashboard';
  static const adminDashboard = '/admin/dashboard';

  static const schedule = '/schedule';
  static const alerts = '/alerts';
  static const profile = '/profile';
  static const changePassword = '/change-password';
  static const notificationSettings = '/settings/notifications';
  static const help = '/help';
  static const announcements = '/announcements';
  static const eventNew = '/events/new';
  static const manageTeachers = '/admin/teachers';
  static const developer = '/developer';
  static const developerApis = '/developer/apis';
  static const developerTasks = '/developer/tasks';
  static const developerFeatureFlags = '/developer/feature-flags';
  static const developerSystemChecks = '/developer/system-checks';
  static const developerModules = '/developer/modules';

  static const assignments = '/assignments';
  static const assignmentNew = '/assignments/new';
  static const grades = '/grades';
  static const gradebook = '/grades/gradebook';
  static const attendance = '/attendance';
  static const attendanceTake = '/attendance/take';
  static const attendanceHistory = '/attendance/history';
  static const chat = '/chat';
  static const chatNew = '/chat/new';
  static const payments = '/payments';
  static const paymentsHistory = '/payments/history';
  static const paymentsReceipt = '/payments/receipt';
  static const paymentsDunning = '/payments/dunning';
  static const reports = '/reports';
  static const accessDenied = '/access-denied';
}
