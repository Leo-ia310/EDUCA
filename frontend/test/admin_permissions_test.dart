import 'package:educa360/core/routing/route_paths.dart';
import 'package:educa360/features/admin/data/admin_permissions.dart';
import 'package:educa360/features/admin/data/admin_profile.dart';
import 'package:educa360/features/admin/data/admin_schedule.dart';
import 'package:educa360/shared/models/app_role.dart';
import 'package:educa360/shared/models/app_user.dart';
import 'package:flutter_test/flutter_test.dart';

AppUser _user(List<String>? permissions) => AppUser(
      id: '1',
      institutionId: 1,
      email: 'juan@demo.com',
      fullName: 'Juan Pérez',
      roles: const [AppRole.coordinator],
      activeRole: AppRole.coordinator,
      adminPermissions: permissions,
    );

void main() {
  test('sin lista de permisos conserva el acceso completo (demo/histórico)',
      () {
    final user = _user(null);
    expect(user.can('roles.edit'), isTrue);
    expect(user.can('students.view'), isTrue);
  });

  test('con lista explícita solo puede lo concedido', () {
    final user = _user(['students.view', 'students.edit', 'payments.view']);
    expect(user.can('students.edit'), isTrue);
    expect(user.can('payments.view'), isTrue);
    expect(user.can('teachers.view'), isFalse);
    expect(user.can('roles.view'), isFalse);
    expect(user.can('settings.view'), isFalse);
    expect(_user(const []).can('dashboard.view'), isFalse);
  });

  test('cada ruta del panel admin exige su permiso de lectura', () {
    expect(permissionForAdminRoute(Routes.manageTeachers), Perm.teachersView);
    expect(permissionForAdminRoute(Routes.adminStudents), Perm.studentsView);
    expect(permissionForAdminRoute(Routes.adminParents), Perm.studentsView);
    expect(
      permissionForAdminRoute('${Routes.adminGroups}/g-1'),
      Perm.classesView,
    );
    expect(permissionForAdminRoute(Routes.adminClasses), Perm.classesView);
    expect(permissionForAdminRoute(Routes.adminRoles), Perm.rolesView);
    expect(permissionForAdminRoute(Routes.adminAccess), 'roles.edit');
    expect(
      permissionForAdminRoute(Routes.adminSchedules),
      Perm.schedulesView,
    );
    expect(permissionForAdminRoute(Routes.paymentsDunning), Perm.paymentsView);
    expect(permissionForAdminRoute(Routes.adminReportCards), Perm.reportsView);
    expect(permissionForAdminRoute(Routes.adminDashboard), isNull);
  });

  test('el catálogo cubre los módulos pedidos y no repite códigos', () {
    final codes = allAdminPermissionCodes;
    expect(codes.toSet().length, codes.length);
    for (final c in [
      'students.delete',
      'teachers.create',
      'classes.edit',
      'payments.cancel',
      'reports.download',
      'roles.delete',
      'dashboard.view',
      'settings.edit',
    ]) {
      expect(codes, contains(c));
    }
  });

  test('AdminProfile.fromJson lee rol y permisos', () {
    final p = AdminProfile.fromJson(const {
      'id': 7,
      'fullName': 'María López',
      'email': 'maria@demo.com',
      'roleCode': 'admin',
      'customized': true,
      'permissions': ['students.view'],
    });
    expect(p.initials, 'ML');
    expect(p.customized, isTrue);
    expect(p.permissions, ['students.view']);
    expect(p.active, isTrue);
  });

  test('AdminScheduleEntry distingue clase y receso', () {
    final cls = AdminScheduleEntry.fromJson(const {
      'id': 1,
      'kind': 'class',
      'weekdayId': 2,
      'startTime': '08:00',
      'endTime': '09:00',
      'subject': 'Matemáticas',
      'teacher': 'Laura Díaz',
      'room': 'Aula 1',
      'shift': 'morning',
    });
    expect(cls.isBreak, isFalse);
    expect(weekdayLabel(cls.weekdayId), 'Martes');
    expect(shiftLabel(cls.shift), 'Mañana');

    final brk = AdminScheduleEntry.fromJson(const {
      'id': 2,
      'kind': 'break',
      'weekdayId': 2,
      'startTime': '10:00',
      'endTime': '10:20',
      'subject': 'Receso',
    });
    expect(brk.isBreak, isTrue);
    expect(brk.groupId, isNull);
    expect(shiftLabel(null), '');
  });
}
