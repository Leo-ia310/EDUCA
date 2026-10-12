import 'package:flutter_test/flutter_test.dart';

import 'package:educa360/shared/models/app_role.dart';

void main() {
  group('AppRole.sortedByPriority', () {
    test('elige administración antes que estudiante cuando ambos existen', () {
      final roles = AppRole.sortedByPriority([
        AppRole.student,
        AppRole.admin,
      ]);

      expect(roles.first, AppRole.admin);
      expect(roles, [AppRole.admin, AppRole.student]);
    });

    test('elimina roles duplicados y mantiene prioridad estable', () {
      final roles = AppRole.sortedByPriority([
        AppRole.parent,
        AppRole.teacher,
        AppRole.parent,
        AppRole.coordinator,
      ]);

      expect(roles, [
        AppRole.coordinator,
        AppRole.teacher,
        AppRole.parent,
      ]);
    });
  });
}
