import 'package:equatable/equatable.dart';

import '../../attendance/domain/entities.dart';

/// Un equipo de trabajo dentro de una clase: agrupa integrantes y lleva una
/// calificación única que se aplica a todos sus miembros.
class WorkTeam extends Equatable {
  const WorkTeam({
    required this.id,
    required this.classId,
    required this.name,
    required this.members,
    this.maxScore = 100,
    this.score,
    this.feedback,
  });

  final String id;
  final int classId;
  final String name;
  final List<StudentBrief> members;
  final double maxScore;

  /// Calificación del equipo (aplica a todos los integrantes). `null` = sin
  /// calificar.
  final double? score;
  final String? feedback;

  bool get isGraded => score != null;

  WorkTeam copyWith({
    String? name,
    List<StudentBrief>? members,
    double? maxScore,
    double? score,
    String? feedback,
    bool clearScore = false,
  }) {
    return WorkTeam(
      id: id,
      classId: classId,
      name: name ?? this.name,
      members: members ?? this.members,
      maxScore: maxScore ?? this.maxScore,
      score: clearScore ? null : (score ?? this.score),
      feedback: feedback ?? this.feedback,
    );
  }

  @override
  List<Object?> get props =>
      [id, classId, name, members, maxScore, score, feedback];
}
