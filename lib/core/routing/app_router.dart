import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/assignments/presentation/screens/assignment_detail_screen.dart';
import '../../features/assignments/presentation/screens/assignment_form_screen.dart';
import '../../features/assignments/presentation/screens/grading_screen.dart';
import '../../features/assignments/presentation/screens/student_assignments_screen.dart';
import '../../features/assignments/presentation/screens/teacher_assignments_screen.dart';
import '../../features/attendance/presentation/screens/attendance_classes_screen.dart';
import '../../features/attendance/presentation/screens/attendance_history_screen.dart';
import '../../features/attendance/presentation/screens/attendance_take_screen.dart';
import '../../features/chat/presentation/screens/chat_screen.dart';
import '../../features/chat/presentation/screens/conversations_screen.dart';
import '../../features/chat/presentation/screens/new_conversation_screen.dart';
import '../../features/notifications/presentation/screens/notifications_screen.dart';
import '../../features/payments/presentation/screens/admin_dunning_screen.dart';
import '../../features/payments/presentation/screens/charge_detail_screen.dart';
import '../../features/payments/presentation/screens/checkout_screen.dart';
import '../../features/payments/presentation/screens/parent_charges_screen.dart';
import '../../features/payments/presentation/screens/payment_history_screen.dart';
import '../../features/grades/presentation/screens/student_grades_screen.dart';
import '../../features/grades/presentation/screens/subject_grades_screen.dart';
import '../../features/grades/presentation/screens/teacher_gradebook_screen.dart';
import '../../features/reports/presentation/report_card_screen.dart';
import '../../features/auth/presentation/auth_controller.dart';
import '../../features/auth/presentation/screens/institution_code_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/splash_screen.dart';
import '../../features/dashboard/presentation/screens/admin_dashboard_screen.dart';
import '../../features/dashboard/presentation/screens/parent_dashboard_screen.dart';
import '../../features/dashboard/presentation/screens/student_dashboard_screen.dart';
import '../../features/dashboard/presentation/screens/teacher_dashboard_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../shared/models/app_role.dart';
import '../widgets/empty_state.dart';
import 'route_paths.dart';

final goRouterProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authControllerProvider);

  return GoRouter(
    initialLocation: Routes.splash,
    debugLogDiagnostics: false,
    refreshListenable: _AuthRefresh(ref),
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final loggedIn = auth.isAuthenticated;
      final goingToAuth = loc == Routes.splash ||
          loc == Routes.institutionCode ||
          loc == Routes.login ||
          loc == Routes.forgotPassword;

      if (!loggedIn && !goingToAuth) return Routes.institutionCode;
      if (loggedIn && goingToAuth) return auth.user!.activeRole.dashboardRoute;
      return null;
    },
    routes: [
      GoRoute(path: Routes.splash, builder: (_, __) => const SplashScreen()),
      GoRoute(
        path: Routes.institutionCode,
        builder: (_, __) => const InstitutionCodeScreen(),
      ),
      GoRoute(path: Routes.login, builder: (_, __) => const LoginScreen()),

      GoRoute(
        path: Routes.studentDashboard,
        builder: (_, __) => const RoleGuard(
          allowed: {AppRole.student},
          child: StudentDashboardScreen(),
        ),
      ),
      GoRoute(
        path: Routes.teacherDashboard,
        builder: (_, __) => const RoleGuard(
          allowed: {AppRole.teacher},
          child: TeacherDashboardScreen(),
        ),
      ),
      GoRoute(
        path: Routes.parentDashboard,
        builder: (_, __) => const RoleGuard(
          allowed: {AppRole.parent},
          child: ParentDashboardScreen(),
        ),
      ),
      GoRoute(
        path: Routes.adminDashboard,
        builder: (_, __) => const RoleGuard(
          allowed: {AppRole.admin, AppRole.coordinator, AppRole.director},
          child: AdminDashboardScreen(),
        ),
      ),

      GoRoute(
        path: Routes.attendance,
        builder: (_, __) => const RoleGuard(
          allowed: {AppRole.teacher, AppRole.admin, AppRole.coordinator, AppRole.director},
          child: AttendanceClassesScreen(),
        ),
      ),
      GoRoute(
        path: Routes.attendanceTake,
        builder: (context, state) {
          final raw = state.uri.queryParameters['classId'];
          final classId = int.tryParse(raw ?? '');
          return RoleGuard(
            allowed: const {
              AppRole.teacher,
              AppRole.admin,
              AppRole.coordinator,
              AppRole.director,
            },
            child: AttendanceTakeScreen(classId: classId),
          );
        },
      ),
      GoRoute(
        path: Routes.attendanceHistory,
        builder: (_, __) => const RoleGuard(
          allowed: {AppRole.teacher, AppRole.admin, AppRole.coordinator, AppRole.director},
          child: AttendanceHistoryScreen(),
        ),
      ),

      // ----- Tareas (assignments) -----
      GoRoute(
        path: Routes.assignments,
        builder: (context, state) {
          // Resolver el screen según el rol del usuario actual.
          return const _AssignmentsRoleSplit();
        },
        routes: [
          GoRoute(
            path: 'new',
            builder: (context, state) {
              final raw = state.uri.queryParameters['classId'];
              final classId = int.tryParse(raw ?? '');
              return RoleGuard(
                allowed: const {AppRole.teacher},
                child: AssignmentFormScreen(classId: classId),
              );
            },
          ),
          GoRoute(
            path: ':id',
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              final raw = state.uri.queryParameters['studentId'];
              final studentId = int.tryParse(raw ?? '');
              return AssignmentDetailScreen(
                assignmentId: id,
                studentId: studentId,
              );
            },
            routes: [
              GoRoute(
                path: 'edit',
                builder: (context, state) => RoleGuard(
                  allowed: const {AppRole.teacher},
                  child: AssignmentFormScreen(
                    assignmentId: state.pathParameters['id'],
                  ),
                ),
              ),
              GoRoute(
                path: 'grade',
                builder: (context, state) => RoleGuard(
                  allowed: const {AppRole.teacher},
                  child: GradingScreen(
                    assignmentId: state.pathParameters['id']!,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),

      // ----- Notas / Boletines -----
      GoRoute(
        path: Routes.grades,
        builder: (context, state) {
          final raw = state.uri.queryParameters['studentId'];
          final studentId = int.tryParse(raw ?? '') ?? 1001;
          return const _GradesRoleSplit();
        },
        routes: [
          GoRoute(
            path: 'gradebook',
            builder: (context, state) => const RoleGuard(
              allowed: {
                AppRole.teacher,
                AppRole.admin,
                AppRole.coordinator,
                AppRole.director,
              },
              child: TeacherGradebookScreen(),
            ),
          ),
          GoRoute(
            path: 'subject/:classId',
            builder: (context, state) {
              final classId =
                  int.tryParse(state.pathParameters['classId'] ?? '') ?? 0;
              final studentId = int.tryParse(
                      state.uri.queryParameters['studentId'] ?? '') ??
                  1001;
              return SubjectGradesScreen(
                studentId: studentId,
                classId: classId,
              );
            },
          ),
        ],
      ),
      GoRoute(
        path: Routes.reports,
        builder: (context, state) {
          final raw = state.uri.queryParameters['studentId'];
          final studentId = int.tryParse(raw ?? '') ?? 1001;
          return ReportCardScreen(studentId: studentId);
        },
      ),

      // ----- Notificaciones -----
      GoRoute(
        path: Routes.alerts,
        builder: (_, __) => const NotificationsScreen(),
      ),

      // ----- Pagos -----
      GoRoute(
        path: Routes.payments,
        builder: (context, state) {
          final raw = state.uri.queryParameters['studentId'];
          final studentId = int.tryParse(raw ?? '') ?? 1001;
          return _PaymentsRoleSplit(studentId: studentId);
        },
        routes: [
          GoRoute(
            path: 'history',
            builder: (context, state) {
              final raw = state.uri.queryParameters['studentId'];
              final studentId = int.tryParse(raw ?? '') ?? 1001;
              return PaymentHistoryScreen(studentId: studentId);
            },
          ),
          GoRoute(
            path: 'dunning',
            builder: (_, __) => const RoleGuard(
              allowed: {
                AppRole.admin,
                AppRole.coordinator,
                AppRole.director,
              },
              child: AdminDunningScreen(),
            ),
          ),
          GoRoute(
            path: ':chargeId',
            builder: (context, state) =>
                ChargeDetailScreen(chargeId: state.pathParameters['chargeId']!),
            routes: [
              GoRoute(
                path: 'checkout',
                builder: (context, state) => CheckoutScreen(
                  chargeId: state.pathParameters['chargeId']!,
                ),
              ),
            ],
          ),
        ],
      ),

      // ----- Chat -----
      GoRoute(
        path: Routes.chat,
        builder: (_, __) => const ConversationsScreen(),
        routes: [
          GoRoute(
            path: 'new',
            builder: (_, __) => const NewConversationScreen(),
          ),
          GoRoute(
            path: ':conversationId',
            builder: (context, state) => ChatScreen(
              conversationId: state.pathParameters['conversationId']!,
            ),
          ),
        ],
      ),

      GoRoute(
        path: Routes.profile,
        builder: (_, __) => const ProfileScreen(),
      ),
      GoRoute(
        path: Routes.accessDenied,
        builder: (_, __) => const Scaffold(
          body: EmptyState(
            icon: Icons.lock_outline,
            title: 'Acceso denegado',
            subtitle: 'No tienes permisos para entrar a esta sección.',
          ),
        ),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: EmptyState(
        icon: Icons.error_outline,
        title: 'Pantalla no encontrada',
        subtitle: state.error?.message,
      ),
    ),
  );
});

class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Ref ref) {
    ref.listen(authControllerProvider, (_, __) => notifyListeners());
  }
}

/// Dispatcher de `/payments`: padre ve su estado de cuenta; admin ve panel
/// de morosidad; estudiante también ve estado (read-only).
class _PaymentsRoleSplit extends ConsumerWidget {
  const _PaymentsRoleSplit({required this.studentId});
  final int studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final role = user?.activeRole ?? AppRole.parent;
    switch (role) {
      case AppRole.admin:
      case AppRole.coordinator:
      case AppRole.director:
        return const AdminDunningScreen();
      case AppRole.parent:
      case AppRole.student:
      case AppRole.teacher:
        return ParentChargesScreen(studentId: studentId);
    }
  }
}

/// Dispatcher de `/grades`: docente ve el gradebook por clase; estudiante y
/// padre ven las notas del estudiante.
class _GradesRoleSplit extends ConsumerWidget {
  const _GradesRoleSplit();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final role = user?.activeRole ?? AppRole.student;
    switch (role) {
      case AppRole.teacher:
      case AppRole.admin:
      case AppRole.coordinator:
      case AppRole.director:
        return const TeacherGradebookScreen();
      case AppRole.student:
      case AppRole.parent:
        return const StudentGradesScreen(studentId: 1001);
    }
  }
}

/// Dispatcher de `/assignments`: muestra lista docente o feed estudiante
/// según el rol activo. Padre ve el feed del hijo seleccionado (de momento,
/// el primero — más adelante se pasa por query param).
class _AssignmentsRoleSplit extends ConsumerWidget {
  const _AssignmentsRoleSplit();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final role = user?.activeRole ?? AppRole.student;
    switch (role) {
      case AppRole.teacher:
        return const TeacherAssignmentsScreen();
      case AppRole.student:
        return const StudentAssignmentsScreen(studentId: 1001);
      case AppRole.parent:
        return const StudentAssignmentsScreen(studentId: 1001);
      case AppRole.admin:
      case AppRole.coordinator:
      case AppRole.director:
        return const TeacherAssignmentsScreen();
    }
  }
}

/// Guard de roles. Si el usuario actual no tiene un rol permitido, muestra
/// pantalla de acceso denegado.
class RoleGuard extends ConsumerWidget {
  const RoleGuard({super.key, required this.allowed, required this.child});

  final Set<AppRole> allowed;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!allowed.contains(user.activeRole)) {
      return const Scaffold(
        body: EmptyState(
          icon: Icons.lock_outline,
          title: 'Acceso denegado',
          subtitle: 'Tu rol no tiene acceso a esta sección.',
        ),
      );
    }
    return child;
  }
}
