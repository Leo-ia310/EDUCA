import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/routing/route_paths.dart';
import '../../auth/presentation/auth_controller.dart';

/// Permisos del panel administrativo (espejo de
/// `backend/src/lib/admin-permissions.ts`). Código = `<modulo>.<accion>`.
/// El backend es quien los hace cumplir; aquí solo se oculta lo que no aplica.
abstract final class Perm {
  static const dashboardView = 'dashboard.view';
  static const studentsView = 'students.view';
  static const teachersView = 'teachers.view';
  static const classesView = 'classes.view';
  static const schedulesView = 'schedules.view';
  static const paymentsView = 'payments.view';
  static const reportsView = 'reports.view';
  static const rolesView = 'roles.view';
  static const settingsView = 'settings.view';

  static String create(String module) => '$module.create';
  static String edit(String module) => '$module.edit';
  static String delete(String module) => '$module.delete';
}

class AdminPermissionAction {
  const AdminPermissionAction(this.key, this.label);
  final String key;
  final String label;
}

class AdminPermissionModule {
  const AdminPermissionModule(this.key, this.label, this.icon, this.actions);
  final String key;
  final String label;
  final IconData icon;
  final List<AdminPermissionAction> actions;

  String code(AdminPermissionAction a) => '$key.${a.key}';
  List<String> get codes => [for (final a in actions) code(a)];
}

const _view = AdminPermissionAction('view', 'Ver');
const _create = AdminPermissionAction('create', 'Crear');
const _edit = AdminPermissionAction('edit', 'Editar');
const _delete = AdminPermissionAction('delete', 'Eliminar');

const adminPermissionModules = <AdminPermissionModule>[
  AdminPermissionModule('dashboard', 'Dashboard', Icons.dashboard_rounded, [
    _view,
  ]),
  AdminPermissionModule('students', 'Alumnos', Icons.backpack_rounded, [
    _view,
    _create,
    _edit,
    _delete,
  ]),
  AdminPermissionModule('teachers', 'Maestros', Icons.badge_rounded, [
    _view,
    _create,
    _edit,
    _delete,
  ]),
  AdminPermissionModule('classes', 'Clases', Icons.menu_book_rounded, [
    _view,
    _create,
    _edit,
    _delete,
  ]),
  AdminPermissionModule('schedules', 'Horarios', Icons.schedule_rounded, [
    _view,
    _create,
    _edit,
    _delete,
  ]),
  AdminPermissionModule('payments', 'Pagos', Icons.payments_rounded, [
    _view,
    _create,
    _edit,
    AdminPermissionAction('cancel', 'Cancelar'),
  ]),
  AdminPermissionModule('reports', 'Reportes', Icons.picture_as_pdf_rounded, [
    _view,
    AdminPermissionAction('generate', 'Generar'),
    AdminPermissionAction('download', 'Descargar'),
  ]),
  AdminPermissionModule(
    'roles',
    'Roles y permisos',
    Icons.admin_panel_settings_rounded,
    [_view, _create, _edit, _delete],
  ),
  AdminPermissionModule('settings', 'Configuración', Icons.settings_rounded, [
    _view,
    AdminPermissionAction('edit', 'Editar'),
  ]),
];

List<String> get allAdminPermissionCodes =>
    [for (final m in adminPermissionModules) ...m.codes];

/// Roles que entran al dashboard admin, con la etiqueta que ve el usuario.
const adminProfileRoles = <(String code, String label)>[
  ('admin', 'Administrador'),
  ('coordinator', 'Supervisor / Coordinador'),
  ('director', 'Director'),
];

/// Permiso de lectura que exige cada ruta del panel admin (null = libre).
String? permissionForAdminRoute(String path) {
  if (path.startsWith(Routes.manageTeachers)) return Perm.teachersView;
  if (path.startsWith(Routes.adminStudents) ||
      path.startsWith(Routes.adminParents)) {
    return Perm.studentsView;
  }
  if (path.startsWith(Routes.adminGroups) ||
      path.startsWith(Routes.adminClasses)) {
    return Perm.classesView;
  }
  if (path.startsWith(Routes.adminSchedules)) return Perm.schedulesView;
  if (path.startsWith(Routes.adminRoles)) return Perm.rolesView;
  if (path.startsWith(Routes.adminReportCards) ||
      path.startsWith(Routes.gradebook)) {
    return Perm.reportsView;
  }
  if (path.startsWith(Routes.paymentsDunning)) return Perm.paymentsView;
  return null;
}

/// ¿El usuario actual puede [code]? Sin lista explícita (demo o cuenta
/// histórica) conserva el acceso completo de su rol.
bool canAdmin(WidgetRef ref, String code) =>
    ref.watch(authControllerProvider).user?.can(code) ?? false;
