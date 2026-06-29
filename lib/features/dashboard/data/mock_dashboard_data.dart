import 'package:flutter/material.dart';

import '../domain/dashboard_models.dart';

class StudentMockData {
  StudentMockData._();

  static const todaySchedule = <ScheduleSlot>[
    ScheduleSlot(
      startTime: '08:00',
      endTime: '09:30',
      subject: 'Matemáticas Avanzadas',
      room: 'Aula 402',
      icon: Icons.calculate_outlined,
    ),
    ScheduleSlot(
      startTime: '09:45',
      endTime: '11:15',
      subject: 'Historia Universal',
      room: 'Aula 108',
      icon: Icons.account_balance_outlined,
    ),
    ScheduleSlot(
      startTime: '11:30',
      endTime: '13:00',
      subject: 'Física Cuántica',
      room: 'Aula 25',
      icon: Icons.science_outlined,
    ),
  ];

  static const subjects = <SubjectProgress>[
    SubjectProgress(
      name: 'Matemáticas',
      teacher: 'Prof. Roberto Bórmez',
      progress: 0.88,
      icon: Icons.calculate_rounded,
    ),
    SubjectProgress(
      name: 'Geografía',
      teacher: 'Prof. Marilus Olivar',
      progress: 0.40,
      icon: Icons.public_rounded,
    ),
  ];

  static const tasks = <TaskBrief>[
    TaskBrief(
      title: 'Ensayo de Ética Prof.',
      subject: 'Subir trabajo',
      status: TaskStatus.pending,
    ),
    TaskBrief(
      title: 'Ecuaciones Diferenciales',
      subject: 'Revisado',
      status: TaskStatus.reviewed,
    ),
  ];

  static const grades = <GradeBrief>[
    GradeBrief(
      subject: 'Matemáticas',
      activity: 'Cálculo Integral',
      score: 9.5,
      status: GradeStatus.passed,
    ),
    GradeBrief(
      subject: 'Historia',
      activity: 'Siglo XIX',
      score: 8.2,
      status: GradeStatus.passed,
    ),
    GradeBrief(
      subject: 'Física',
      activity: 'Termodinámica',
      score: 7.8,
      status: GradeStatus.pending,
    ),
  ];

  static const averageScore = 8.5;
  static const pendingTasks = 3;
  static const classmates = <String>[
    'Ana López',
    'Luis Pérez',
    'Carla Soto',
    'Mario Díaz',
  ];
  static const classmatesExtra = 14;
}

class AttendanceLine {
  const AttendanceLine(this.name, {required this.present});
  final String name;
  final bool present;
}

class TeacherClass {
  const TeacherClass({
    required this.name,
    required this.room,
    required this.icon,
  });
  final String name;
  final String room;
  final IconData icon;
}

class UpcomingAssignment {
  const UpcomingAssignment({
    required this.title,
    required this.meta,
    required this.delivered,
    required this.total,
    this.urgent = false,
    this.completed = false,
  });
  final String title;
  final String meta;
  final int delivered;
  final int total;
  final bool urgent;
  final bool completed;
}

class RecentGrade {
  const RecentGrade(this.student, this.topic, this.score, this.when);
  final String student;
  final String topic;
  final double score;
  final String when;
}

class TeacherMockData {
  TeacherMockData._();

  static const quickAttendance = <AttendanceLine>[
    AttendanceLine('Ana Martínez', present: true),
    AttendanceLine('Bruno García', present: true),
    AttendanceLine('Carla López', present: false),
  ];

  static const myClasses = <TeacherClass>[
    TeacherClass(
      name: 'Matemáticas Avanzadas',
      room: 'Aula 204',
      icon: Icons.functions_rounded,
    ),
    TeacherClass(
      name: 'Geometría',
      room: 'Aula 110',
      icon: Icons.architecture_rounded,
    ),
  ];

  static const upcomingAssignments = <UpcomingAssignment>[
    UpcomingAssignment(
      title: 'Examen Parcial II',
      meta: 'Límite: Mañana · 4° Grado A',
      delivered: 12,
      total: 24,
      urgent: true,
    ),
    UpcomingAssignment(
      title: 'Práctica de Ecuaciones',
      meta: 'Límite: 26 Sept · 4° Grado A',
      delivered: 20,
      total: 22,
    ),
    UpcomingAssignment(
      title: 'Investigación de Pitágoras',
      meta: 'Pendiente · 4° Grado B',
      delivered: 24,
      total: 24,
      completed: true,
    ),
  ];

  static const recentGrades = <RecentGrade>[
    RecentGrade('Diego Rivas', 'Tema: Logaritmos', 9.5, 'Hoy 10:30'),
    RecentGrade('Sofía Méndez', 'Tema: Cálculo', 8.2, 'Hoy 09:11'),
    RecentGrade('Javier Sosa', 'Tema: Derivadas', 10.0, 'Ayer'),
  ];

  static const pendingClasses = 3;
  static const pendingGrading = 12;
}

class ChildBrief {
  const ChildBrief(this.name, {this.selected = false});
  final String name;
  final bool selected;
}

class ParentSubject {
  const ParentSubject(this.name, this.teacher);
  final String name;
  final String teacher;
}

class ParentActivity {
  const ParentActivity({
    required this.tag,
    required this.title,
    required this.score,
    required this.timeAgo,
    required this.progress,
  });
  final String tag;
  final String title;
  final String score;
  final String timeAgo;
  final double progress;
}

class ParentMockData {
  ParentMockData._();

  static const children = <ChildBrief>[
    ChildBrief('Mateo', selected: true),
    ChildBrief('Sofía'),
  ];

  static const attendancePercent = 98.0;
  static const monthEvents = 12;
  static const newNotices = 3;

  static const subjects = <ParentSubject>[
    ParentSubject('Matemáticas Avanzadas', 'Prof. Ricardo Méndez'),
    ParentSubject('Biología Celular', 'Prof. Elena Santís'),
  ];

  static const recentActivity = <ParentActivity>[
    ParentActivity(
      tag: 'Nueva Nota',
      title: 'Examen Bimestral: Álgebra',
      score: '9.5/10',
      timeAgo: 'Entregado hace 2 horas',
      progress: 0.95,
    ),
    ParentActivity(
      tag: 'Calificado',
      title: 'Ensayo de Literatura',
      score: '',
      timeAgo: 'Estatus: Calificado',
      progress: 1.0,
    ),
  ];
}

class Announcement {
  const Announcement(this.title, this.body);
  final String title;
  final String body;
}

class AdminTeacher {
  const AdminTeacher(this.name, this.subject);
  final String name;
  final String subject;
}

class AdminMockData {
  AdminMockData._();

  static const attendancePct = 94.2;
  static const institutionalAvg = 8.5;
  static const totalStudents = 1248;
  static const activeTeachers = 56;
  static const upcomingEvents = 12;
  static const systemAlerts = 3;

  static const announcements = <Announcement>[
    Announcement(
      'Reunión de Padres Trimestral',
      'Discusión sobre nuevos lineamientos de tecnología y plan de becas 2026.',
    ),
    Announcement(
      'Feria de Ciencias 2026',
      'Convocatoria abierta a estudiantes para presentar proyectos.',
    ),
    Announcement(
      'Mantenimiento de Servidores',
      'El portal EduCore estará fuera de servicio el sábado por la noche.',
    ),
  ];

  static const teachers = <AdminTeacher>[
    AdminTeacher('Prof. Carlos Mendoza', 'Matemáticas Avanzadas'),
    AdminTeacher('Dra. Elena Ruiz', 'Ciencias Biológicas'),
    AdminTeacher('Liz. Roberto Díaz', 'Historia Universal'),
  ];
}
