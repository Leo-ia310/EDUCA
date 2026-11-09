import 'dart:async';

import 'package:educa360/features/auth/data/mock_auth_repository.dart';
import 'package:educa360/features/auth/presentation/auth_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late StreamController<void> ended;
  late AuthController controller;

  setUp(() async {
    ended = StreamController<void>.broadcast();
    controller =
        AuthController(MockAuthRepository(), sessionEnded: ended.stream);
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  tearDown(() async {
    controller.dispose();
    await ended.close();
  });

  test('si la sesión termina por fuera, vuelve al login con un aviso',
      () async {
    final role = await controller.signIn('alumno@student.educa', 'demo1234');
    expect(role, isNotNull, reason: 'el login de demostración funciona');
    expect(controller.state.isAuthenticated, isTrue);

    ended.add(null); // p. ej. cerraron sesión en otro dispositivo
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(controller.state.isAuthenticated, isFalse);
    expect(
        controller.state.error, 'Tu sesión terminó. Inicia sesión nuevamente.',);
  });

  test('un cierre normal no muestra el aviso de sesión terminada', () async {
    await controller.signIn('alumno@student.educa', 'demo1234');
    await controller.signOut();
    ended.add(null); // el evento signedOut del propio cierre
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(controller.state.isAuthenticated, isFalse);
    expect(controller.state.error, isNull);
  });
}
