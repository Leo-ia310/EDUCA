import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

class ScheduleSlot extends Equatable {
  const ScheduleSlot({
    required this.startTime,
    required this.endTime,
    required this.subject,
    required this.room,
    this.teacher,
    this.icon,
    this.accent,
  });

  final String startTime;
  final String endTime;
  final String subject;
  final String room;
  final String? teacher;
  final IconData? icon;
  final Color? accent;

  @override
  List<Object?> get props => [startTime, subject, room];
}

class SubjectProgress extends Equatable {
  const SubjectProgress({
    required this.name,
    required this.teacher,
    required this.progress,
    this.icon,
    this.color,
  });

  final String name;
  final String teacher;
  final double progress;
  final IconData? icon;
  final Color? color;

  @override
  List<Object?> get props => [name, teacher, progress];
}

class TaskBrief extends Equatable {
  const TaskBrief({
    required this.title,
    required this.subject,
    required this.status,
    this.dueDate,
  });

  final String title;
  final String subject;
  final TaskStatus status;
  final String? dueDate;

  @override
  List<Object?> get props => [title, subject, status, dueDate];
}

enum TaskStatus { pending, submitted, reviewed, late }

class GradeBrief extends Equatable {
  const GradeBrief({
    required this.subject,
    required this.activity,
    required this.score,
    required this.status,
  });

  final String subject;
  final String activity;
  final double score;
  final GradeStatus status;

  @override
  List<Object?> get props => [subject, activity, score];
}

enum GradeStatus { passed, pending, lowPerformance }
