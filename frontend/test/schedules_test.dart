import 'package:educa360/features/admin/data/admin_schedule.dart';
import 'package:educa360/features/admin/data/demo_schedules.dart';
import 'package:educa360/features/admin/data/school_directory.dart';
import 'package:educa360/features/schedule/providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DemoSchedulesNotifier', () {
    const dir = SchoolDirectory(
      groups: [SchoolGroup(id: 'g-4a', name: '4° Grado A')],
      classes: [
        SchoolClass(
          id: 'c1',
          subject: 'Matemáticas',
          groupId: 'g-4a',
          teacherId: 't1',
        ),
      ],
    );

    test('arranca con el horario de ejemplo (clases y receso)', () {
      final store = DemoSchedulesNotifier();
      expect(store.state, isNotEmpty);
      expect(store.state.any((e) => e.isBreak), isTrue);
    });

    test('detecta choque de grupo, receso y horas contiguas permitidas', () {
      final store = DemoSchedulesNotifier();
      // Lunes 08:00–09:30 ya existe para g-4a.
      expect(
        store.conflictFor(
          weekdayId: 1,
          start: '09:00',
          end: '10:00',
          isBreak: false,
          groupId: 'g-4a',
          dir: dir,
        ),
        contains('el grupo ya tiene'),
      );
      // Otro grupo en el mismo tramo no choca.
      expect(
        store.conflictFor(
          weekdayId: 1,
          start: '09:00',
          end: '10:00',
          isBreak: false,
          groupId: 'g-4b',
          dir: dir,
        ),
        isNull,
      );
      // Contiguo al final de la clase (09:30) no choca.
      expect(
        store.conflictFor(
          weekdayId: 1,
          start: '09:30',
          end: '09:45',
          isBreak: false,
          groupId: 'g-4a',
          dir: dir,
        ),
        isNull,
      );
      // Un receso general encima de una clase choca.
      expect(
        store.conflictFor(
          weekdayId: 1,
          start: '08:30',
          end: '08:50',
          isBreak: true,
          groupId: null,
          dir: dir,
        ),
        contains('se cruza con'),
      );
    });

    test('agrega en varios días, edita y elimina', () {
      final store = DemoSchedulesNotifier();
      final before = store.state.length;
      store.add(
        weekdayIds: [6, 7],
        isBreak: false,
        subject: 'Robótica',
        startTime: '10:00',
        endTime: '11:00',
        groupId: 'g-4a',
        shift: 'morning',
      );
      expect(store.state.length, before + 2);
      final created = store.state.last;
      store.update(
        AdminScheduleEntry(
          id: created.id,
          kind: created.kind,
          weekdayId: created.weekdayId,
          startTime: '10:15',
          endTime: '11:15',
          subject: created.subject,
        ),
      );
      expect(
        store.state.firstWhere((e) => e.id == created.id).startTime,
        '10:15',
      );
      store.remove(created.id);
      expect(store.state.length, before + 1);
    });
  });

  test('buildWeeklySlots agrupa por día, ordena y conserva recesos y turno', () {
    final byDay = buildWeeklySlots([
      {
        'weekdayIndex': 0,
        'kind': 'class',
        'subject': 'Matemáticas',
        'startTime': '09:00',
        'endTime': '10:00',
        'room': 'Aula 1',
        'teacher': 'Laura Díaz',
        'shift': 'morning',
      },
      {
        'weekdayIndex': 0,
        'kind': 'break',
        'subject': 'Receso',
        'startTime': '08:00',
        'endTime': '08:20',
        'room': 'no debe verse',
        'shift': null,
      },
      {
        'weekdayIndex': 5,
        'kind': 'class',
        'subject': 'Robótica',
        'startTime': '10:00',
        'endTime': '11:00',
      },
    ]);
    expect(byDay.keys.toSet(), {0, 5});
    expect(byDay[0]!.map((s) => s.start), ['08:00', '09:00']);
    expect(byDay[0]!.first.isBreak, isTrue);
    expect(byDay[0]!.first.room, isEmpty);
    expect(byDay[0]!.last.shift, 'morning');
    expect(byDay[0]!.last.teacher, 'Laura Díaz');
  });
}
