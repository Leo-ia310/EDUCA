import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/env.dart';
import '../../../shared/models/app_role.dart';
import '../../assignments/data/mock_assignments_data.dart';

/// Persona del colegio (maestro, alumno, padre, coordinador, director…). Un
/// único modelo con `role` alimenta los CRUD de Maestros, Alumnos, Padres y el
/// de Roles y perfiles.
class Person {
  const Person({
    required this.id,
    required this.name,
    required this.role,
    this.email = '',
    this.phone = '',
    this.active = true,
    this.groupId,
    this.classIds = const {},
    this.childIds = const {},
  });

  final String id;
  final String name;
  final AppRole role;
  final String email;
  final String phone;
  final bool active;

  /// Alumno: salón/año al que pertenece.
  final String? groupId;

  /// Alumno: clases en las que está inscrito.
  final Set<String> classIds;

  /// Padre/tutor: alumnos a su cargo.
  final Set<String> childIds;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    final a = parts.first[0];
    final b = parts.length > 1 ? parts[1][0] : '';
    return (a + b).toUpperCase();
  }

  Person copyWith({
    String? name,
    AppRole? role,
    String? email,
    String? phone,
    bool? active,
    String? groupId,
    bool clearGroup = false,
    Set<String>? classIds,
    Set<String>? childIds,
  }) =>
      Person(
        id: id,
        name: name ?? this.name,
        role: role ?? this.role,
        email: email ?? this.email,
        phone: phone ?? this.phone,
        active: active ?? this.active,
        groupId: clearGroup ? null : (groupId ?? this.groupId),
        classIds: classIds ?? this.classIds,
        childIds: childIds ?? this.childIds,
      );
}

/// Salón / año ("4° Grado A").
class SchoolGroup {
  const SchoolGroup({required this.id, required this.name});
  final String id;
  final String name;
}

/// Clase: materia dictada en un salón por un maestro.
class SchoolClass {
  const SchoolClass({
    required this.id,
    required this.subject,
    required this.groupId,
    this.teacherId,
    this.room = '',
  });

  final String id;
  final String subject;
  final String groupId;
  final String? teacherId;
  final String room;

  SchoolClass copyWith({
    String? subject,
    String? groupId,
    String? teacherId,
    bool clearTeacher = false,
    String? room,
  }) =>
      SchoolClass(
        id: id,
        subject: subject ?? this.subject,
        groupId: groupId ?? this.groupId,
        teacherId: clearTeacher ? null : (teacherId ?? this.teacherId),
        room: room ?? this.room,
      );
}

class SchoolDirectory {
  const SchoolDirectory({
    this.people = const [],
    this.groups = const [],
    this.classes = const [],
  });

  final List<Person> people;
  final List<SchoolGroup> groups;
  final List<SchoolClass> classes;

  List<Person> byRole(AppRole role) =>
      people.where((p) => p.role == role).toList();

  Person? person(String? id) {
    for (final p in people) {
      if (p.id == id) return p;
    }
    return null;
  }

  SchoolGroup? group(String? id) {
    for (final g in groups) {
      if (g.id == id) return g;
    }
    return null;
  }

  SchoolClass? classById(String? id) {
    for (final c in classes) {
      if (c.id == id) return c;
    }
    return null;
  }

  List<SchoolClass> classesOfTeacher(String teacherId) =>
      classes.where((c) => c.teacherId == teacherId).toList();

  List<SchoolClass> classesOfGroup(String groupId) =>
      classes.where((c) => c.groupId == groupId).toList();

  List<Person> studentsOfGroup(String groupId) => people
      .where((p) => p.role == AppRole.student && p.groupId == groupId)
      .toList();

  List<Person> guardiansOf(String studentId) => people
      .where((p) => p.role == AppRole.parent && p.childIds.contains(studentId))
      .toList();
}

/// CRUD en memoria del directorio institucional (salones, clases, personas).
/// En demo arranca con datos de ejemplo; mientras no exista backend para
/// estas operaciones, los cambios viven solo durante la sesión.
class SchoolDirectoryNotifier extends StateNotifier<SchoolDirectory> {
  SchoolDirectoryNotifier()
      : super(Env.isDemoMode ? _seed() : const SchoolDirectory());

  int _seq = 100;
  String _newId(String prefix) => '$prefix-${_seq++}';

  // ---------- Personas ----------
  Person addPerson(Person draft) {
    final p = Person(
      id: _newId('p'),
      name: draft.name,
      role: draft.role,
      email: draft.email,
      phone: draft.phone,
      active: draft.active,
      groupId: draft.groupId,
      classIds: draft.classIds,
      childIds: draft.childIds,
    );
    state = SchoolDirectory(
      people: [...state.people, p],
      groups: state.groups,
      classes: state.classes,
    );
    return p;
  }

  void updatePerson(Person p) {
    state = SchoolDirectory(
      people: [for (final x in state.people) x.id == p.id ? p : x],
      groups: state.groups,
      classes: state.classes,
    );
  }

  void removePerson(String id) {
    state = SchoolDirectory(
      people: [
        for (final x in state.people)
          if (x.id != id)
            x.childIds.contains(id)
                ? x.copyWith(childIds: {...x.childIds}..remove(id))
                : x,
      ],
      groups: state.groups,
      // Un maestro eliminado deja sus clases sin asignar.
      classes: [
        for (final c in state.classes)
          c.teacherId == id ? c.copyWith(clearTeacher: true) : c,
      ],
    );
  }

  /// Pasa a un alumno de salón: queda inscrito en las clases del nuevo salón.
  void moveStudent(String studentId, String? groupId) {
    final s = state.person(studentId);
    if (s == null) return;
    final ids = groupId == null
        ? <String>{}
        : state.classesOfGroup(groupId).map((c) => c.id).toSet();
    updatePerson(
      groupId == null
          ? s.copyWith(clearGroup: true, classIds: ids)
          : s.copyWith(groupId: groupId, classIds: ids),
    );
  }

  // ---------- Salones ----------
  SchoolGroup addGroup(String name) {
    final g = SchoolGroup(id: _newId('g'), name: name);
    state = SchoolDirectory(
      people: state.people,
      groups: [...state.groups, g],
      classes: state.classes,
    );
    return g;
  }

  void renameGroup(String id, String name) {
    state = SchoolDirectory(
      people: state.people,
      groups: [
        for (final g in state.groups)
          g.id == id ? SchoolGroup(id: id, name: name) : g,
      ],
      classes: state.classes,
    );
  }

  void removeGroup(String id) {
    final removedClasses = state.classesOfGroup(id).map((c) => c.id).toSet();
    state = SchoolDirectory(
      people: [
        for (final p in state.people)
          p.groupId == id
              ? p.copyWith(
                  clearGroup: true,
                  classIds: p.classIds.difference(removedClasses),
                )
              : p,
      ],
      groups: [
        for (final g in state.groups)
          if (g.id != id) g,
      ],
      classes: [
        for (final c in state.classes)
          if (c.groupId != id) c,
      ],
    );
  }

  // ---------- Clases ----------
  SchoolClass addClass(SchoolClass draft) {
    final c = SchoolClass(
      id: _newId('c'),
      subject: draft.subject,
      groupId: draft.groupId,
      teacherId: draft.teacherId,
      room: draft.room,
    );
    state = SchoolDirectory(
      // Los alumnos del salón quedan inscritos en la nueva clase.
      people: [
        for (final p in state.people)
          p.role == AppRole.student && p.groupId == c.groupId
              ? p.copyWith(classIds: {...p.classIds, c.id})
              : p,
      ],
      groups: state.groups,
      classes: [...state.classes, c],
    );
    return c;
  }

  /// Edita una clase (incluye reasignar maestro o cambiar de salón).
  void updateClass(SchoolClass c) {
    final old = state.classById(c.id);
    final movedGroup = old != null && old.groupId != c.groupId;
    state = SchoolDirectory(
      people: [
        for (final p in state.people)
          if (movedGroup && p.role == AppRole.student)
            // Sale de la clase quien no esté en el nuevo salón y entra quien sí.
            p.copyWith(
              classIds: p.groupId == c.groupId
                  ? {...p.classIds, c.id}
                  : ({...p.classIds}..remove(c.id)),
            )
          else
            p,
      ],
      groups: state.groups,
      classes: [for (final x in state.classes) x.id == c.id ? c : x],
    );
  }

  void removeClass(String id) {
    state = SchoolDirectory(
      people: [
        for (final p in state.people)
          p.classIds.contains(id)
              ? p.copyWith(classIds: {...p.classIds}..remove(id))
              : p,
      ],
      groups: state.groups,
      classes: [
        for (final c in state.classes)
          if (c.id != id) c,
      ],
    );
  }

  /// Asigna (o quita, con `null`) el maestro de una clase.
  void assignTeacher(String classId, String? teacherId) {
    final c = state.classById(classId);
    if (c == null) return;
    updateClass(
      teacherId == null
          ? c.copyWith(clearTeacher: true)
          : c.copyWith(teacherId: teacherId),
    );
  }
}

final schoolDirectoryProvider =
    StateNotifierProvider<SchoolDirectoryNotifier, SchoolDirectory>(
  (ref) => SchoolDirectoryNotifier(),
);

SchoolDirectory _seed() {
  const groups = [
    SchoolGroup(id: 'g-4a', name: '4° Grado A'),
    SchoolGroup(id: 'g-4b', name: '4° Grado B'),
    SchoolGroup(id: 'g-5a', name: '5° Grado A'),
  ];

  const teachers = [
    ('t-ricardo', 'Ricardo Méndez', 'ricardo.mendez@colegio.edu'),
    ('t-elena', 'Elena Santís', 'elena.santis@colegio.edu'),
    ('t-marta', 'Marta Vega', 'marta.vega@colegio.edu'),
    ('t-andres', 'Andrés Paz', 'andres.paz@colegio.edu'),
    ('t-laura', 'Laura Díaz', 'laura.diaz@colegio.edu'),
    ('t-carlos', 'Carlos Mendoza', 'carlos.mendoza@colegio.edu'),
  ];

  const classes = [
    SchoolClass(
      id: 'c-mat-4a',
      subject: 'Matemáticas Avanzadas',
      groupId: 'g-4a',
      teacherId: 't-ricardo',
      room: 'Aula 204',
    ),
    SchoolClass(
      id: 'c-bio-4a',
      subject: 'Biología Celular',
      groupId: 'g-4a',
      teacherId: 't-elena',
      room: 'Lab 2',
    ),
    SchoolClass(
      id: 'c-his-4a',
      subject: 'Historia Universal',
      groupId: 'g-4a',
      teacherId: 't-marta',
      room: 'Aula 110',
    ),
    SchoolClass(
      id: 'c-mat-4b',
      subject: 'Matemáticas Avanzadas',
      groupId: 'g-4b',
      teacherId: 't-ricardo',
      room: 'Aula 205',
    ),
    SchoolClass(
      id: 'c-len-4b',
      subject: 'Lengua y Literatura',
      groupId: 'g-4b',
      teacherId: 't-andres',
      room: 'Aula 112',
    ),
    SchoolClass(
      id: 'c-fis-5a',
      subject: 'Física Cuántica',
      groupId: 'g-5a',
      teacherId: 't-carlos',
      room: 'Lab 1',
    ),
    SchoolClass(
      id: 'c-geo-5a',
      subject: 'Geometría',
      groupId: 'g-5a',
      teacherId: 't-laura',
      room: 'Aula 301',
    ),
  ];

  final people = <Person>[
    for (final t in teachers)
      Person(
        id: t.$1,
        name: t.$2,
        role: AppRole.teacher,
        email: t.$3,
        phone: '+51 900 000 ${t.$1.length}0${t.$1.length}',
      ),
  ];

  // Alumnos (ids 1001–1012, los mismos del demo de notas y boletines).
  final groupIds = [
    'g-4a',
    'g-4a',
    'g-4a',
    'g-4a',
    'g-4b',
    'g-4b',
    'g-4b',
    'g-4b',
    'g-5a',
    'g-5a',
    'g-5a',
    'g-5a',
  ];
  var i = 0;
  for (final e in AssignmentsMockSeed.studentNames.entries) {
    final gid = groupIds[i % groupIds.length];
    people.add(
      Person(
        id: '${e.key}',
        name: e.value,
        role: AppRole.student,
        email:
            '${e.value.toLowerCase().replaceAll(' ', '.').replaceAll(RegExp('[áàä]'), 'a').replaceAll(RegExp('[éèë]'), 'e').replaceAll(RegExp('[íìï]'), 'i').replaceAll(RegExp('[óòö]'), 'o').replaceAll(RegExp('[úùü]'), 'u')}@alumnos.edu',
        groupId: gid,
        classIds:
            classes.where((c) => c.groupId == gid).map((c) => c.id).toSet(),
      ),
    );
    i++;
  }

  people.addAll(const [
    Person(
      id: 'pa-1',
      name: 'Marta Martínez',
      role: AppRole.parent,
      email: 'marta.martinez@correo.com',
      phone: '+51 911 111 111',
      childIds: {'1001'},
    ),
    Person(
      id: 'pa-2',
      name: 'Jorge García',
      role: AppRole.parent,
      email: 'jorge.garcia@correo.com',
      phone: '+51 922 222 222',
      childIds: {'1002', '1006'},
    ),
    Person(
      id: 'pa-3',
      name: 'Lucía López',
      role: AppRole.parent,
      email: 'lucia.lopez@correo.com',
      phone: '+51 933 333 333',
      childIds: {'1003'},
    ),
    Person(
      id: 'co-1',
      name: 'Patricia Rojas',
      role: AppRole.coordinator,
      email: 'patricia.rojas@colegio.edu',
    ),
    Person(
      id: 'ad-1',
      name: 'Daniel Torres',
      role: AppRole.admin,
      email: 'daniel.torres@colegio.edu',
    ),
    Person(
      id: 'di-1',
      name: 'Rosa Elena Quispe',
      role: AppRole.director,
      email: 'direccion@colegio.edu',
    ),
  ]);

  return SchoolDirectory(people: people, groups: groups, classes: classes);
}
