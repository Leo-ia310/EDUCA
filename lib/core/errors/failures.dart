import 'package:equatable/equatable.dart';

/// Tipo padre de errores de dominio. Repositorios/use-cases lanzan
/// [Failure]; presentación los traduce a mensajes.
sealed class Failure extends Equatable implements Exception {
  const Failure(this.message, {this.cause});
  final String message;
  final Object? cause;

  @override
  List<Object?> get props => [message, cause];
}

class AuthFailure extends Failure {
  const AuthFailure(super.message, {super.cause});
}

class NetworkFailure extends Failure {
  const NetworkFailure(super.message, {super.cause});
}

class ServerFailure extends Failure {
  const ServerFailure(super.message, {super.cause});
}

class CacheFailure extends Failure {
  const CacheFailure(super.message, {super.cause});
}

class ValidationFailure extends Failure {
  const ValidationFailure(super.message, {super.cause});
}

class PermissionFailure extends Failure {
  const PermissionFailure(super.message, {super.cause});
}
