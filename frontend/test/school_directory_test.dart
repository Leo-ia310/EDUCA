import 'package:educa360/features/admin/data/school_directory.dart';
import 'package:educa360/shared/models/app_role.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late SchoolDirectoryNotifier store;
  late SchoolGroup g1;
  late SchoolGroup g2;
  late SchoolClass math;
  late Person t1;
  late Person t2;
  late Person student;

  setUp(() {
    store = SchoolDirectoryNotifier();
    g1 = store.addGroup('4° A');
    g2 = store.addGroup('4° B');
    t1 = store.addPerson(
      const Person(id: '', name: 'Ana', role: AppRole.teacher),
    );
    t2 = store.addPerson(
      const Person(id: '', name: 'Beto', role: AppRole.teacher),
    );
    math = store.addClass(
      SchoolClass(id: '', subject: 'Mate', groupId: g1.id, teacherId: t1.id),
    );
    store.addClass(SchoolClass(id: '', subject: 'Arte', groupId: g2.id));
    student = store.addPerson(
      Person(id: '', name: 'Luis', role: AppRole.student, groupId: g1.id),
    );
  });

  test('una clase nueva inscribe a los alumnos del salón', () {
    final c = store.addClass(
      SchoolClass(id: '', subject: 'Física', groupId: g1.id),
    );
    expect(store.state.person(student.id)!.classIds, contains(c.id));
  });

  test('cambiar el maestro de una clase', () {
    store.assignTeacher(math.id, t2.id);
    expect(store.state.classById(math.id)!.teacherId, t2.id);
    expect(store.state.classesOfTeacher(t1.id), isEmpty);
    expect(store.state.classesOfTeacher(t2.id).length, 1);
  });

  test('mover un alumno de salón lo inscribe en las clases del nuevo', () {
    store.moveStudent(student.id, g2.id);
    final s = store.state.person(student.id)!;
    expect(s.groupId, g2.id);
    expect(s.classIds, store.state.classesOfGroup(g2.id).map((c) => c.id));
  });

  test('cambiar una clase de salón actualiza las inscripciones', () {
    store.updateClass(store.state.classById(math.id)!.copyWith(groupId: g2.id));
    expect(store.state.person(student.id)!.classIds, isNot(contains(math.id)));
  });

  test('eliminar un maestro deja sus clases sin asignar', () {
    store.removePerson(t1.id);
    expect(store.state.classById(math.id)!.teacherId, isNull);
  });

  test('eliminar un alumno lo quita de los padres', () {
    final p = store.addPerson(
      Person(
        id: '',
        name: 'Madre',
        role: AppRole.parent,
        childIds: {student.id},
      ),
    );
    store.removePerson(student.id);
    expect(store.state.person(p.id)!.childIds, isEmpty);
  });

  test('eliminar un salón elimina sus clases y desvincula alumnos', () {
    store.removeGroup(g1.id);
    expect(store.state.classById(math.id), isNull);
    final s = store.state.person(student.id)!;
    expect(s.groupId, isNull);
    expect(s.classIds, isEmpty);
  });
}
