import '../domain/entities.dart';

/// Clases mock que se muestran al maestro en modo demo. Cualquier `classId`
/// debe ser único en este conjunto.
class AttendanceMock {
  AttendanceMock._();

  static final todaysClasses = <ClassSessionBrief>[
    const ClassSessionBrief(
      classId: 101,
      groupId: 4001,
      subjectName: 'Matemáticas Avanzadas',
      groupName: '4° Grado A',
      startTime: '08:00',
      endTime: '09:30',
      classroom: 'Aula 204',
      studentCount: 24,
    ),
    const ClassSessionBrief(
      classId: 102,
      groupId: 4002,
      subjectName: 'Geometría',
      groupName: '4° Grado B',
      startTime: '10:00',
      endTime: '11:30',
      classroom: 'Aula 110',
      studentCount: 22,
    ),
    const ClassSessionBrief(
      classId: 103,
      groupId: 4003,
      subjectName: 'Cálculo Diferencial',
      groupName: '5° Grado A',
      startTime: '13:30',
      endTime: '15:00',
      classroom: 'Aula 25',
      studentCount: 18,
    ),
  ];

  /// Estudiantes inscritos por clase. Los ids son estables para que los Hive
  /// boxes sigan apuntando al mismo estudiante entre cierres de app.
  static final roster = <int, List<StudentBrief>>{
    101: const [
      StudentBrief(id: 1001, fullName: 'Ana Martínez', studentCode: 'A-1001'),
      StudentBrief(id: 1002, fullName: 'Bruno García', studentCode: 'A-1002'),
      StudentBrief(id: 1003, fullName: 'Carla López', studentCode: 'A-1003'),
      StudentBrief(id: 1004, fullName: 'Diego Rivas', studentCode: 'A-1004'),
      StudentBrief(id: 1005, fullName: 'Elena Soto', studentCode: 'A-1005'),
      StudentBrief(id: 1006, fullName: 'Felipe Méndez', studentCode: 'A-1006'),
      StudentBrief(id: 1007, fullName: 'Gabriela Ruiz', studentCode: 'A-1007'),
      StudentBrief(id: 1008, fullName: 'Hugo Padilla', studentCode: 'A-1008'),
      StudentBrief(id: 1009, fullName: 'Isabel Vargas', studentCode: 'A-1009'),
      StudentBrief(id: 1010, fullName: 'Javier Sosa', studentCode: 'A-1010'),
      StudentBrief(id: 1011, fullName: 'Karla Núñez', studentCode: 'A-1011'),
      StudentBrief(id: 1012, fullName: 'Luis Herrera', studentCode: 'A-1012'),
    ],
    102: const [
      StudentBrief(id: 2001, fullName: 'María Castillo', studentCode: 'B-2001'),
      StudentBrief(id: 2002, fullName: 'Nicolás Ruiz', studentCode: 'B-2002'),
      StudentBrief(id: 2003, fullName: 'Olivia Torres', studentCode: 'B-2003'),
      StudentBrief(id: 2004, fullName: 'Pedro Morán', studentCode: 'B-2004'),
      StudentBrief(id: 2005, fullName: 'Renata Solís', studentCode: 'B-2005'),
      StudentBrief(id: 2006, fullName: 'Samuel Báez', studentCode: 'B-2006'),
      StudentBrief(id: 2007, fullName: 'Tania López', studentCode: 'B-2007'),
      StudentBrief(id: 2008, fullName: 'Uriel Pérez', studentCode: 'B-2008'),
    ],
    103: const [
      StudentBrief(id: 3001, fullName: 'Vanessa Acosta', studentCode: 'C-3001'),
      StudentBrief(id: 3002, fullName: 'Walter Salinas', studentCode: 'C-3002'),
      StudentBrief(id: 3003, fullName: 'Ximena Cruz', studentCode: 'C-3003'),
      StudentBrief(id: 3004, fullName: 'Yamil Ortega', studentCode: 'C-3004'),
      StudentBrief(id: 3005, fullName: 'Zoe Mendieta', studentCode: 'C-3005'),
    ],
  };

  static List<StudentBrief> studentsOf(int classId) =>
      roster[classId] ?? const [];

  static String subjectOf(int classId) =>
      todaysClasses.firstWhere(
        (c) => c.classId == classId,
        orElse: () => const ClassSessionBrief(
          classId: -1,
          groupId: -1,
          subjectName: 'Clase',
          groupName: '—',
          startTime: '—',
          endTime: '—',
          studentCount: 0,
        ),
      ).subjectName;

  static String groupOf(int classId) =>
      todaysClasses.firstWhere(
        (c) => c.classId == classId,
        orElse: () => const ClassSessionBrief(
          classId: -1,
          groupId: -1,
          subjectName: '—',
          groupName: '—',
          startTime: '—',
          endTime: '—',
          studentCount: 0,
        ),
      ).groupName;
}
