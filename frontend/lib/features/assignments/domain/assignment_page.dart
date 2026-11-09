import 'entities.dart';

class AssignmentQuery {
  const AssignmentQuery(
      {this.classId,
      this.kinds,
      this.onlyOpen = false,
      this.search = '',
      this.subject,});
  final int? classId;
  final List<AssignmentKind>? kinds;
  final bool onlyOpen;
  final String search;
  final String? subject;
}

/// Conteo ligero de tareas de una clase (tarjetas del panel docente).
class ClassAssignmentCounts {
  const ClassAssignmentCounts({this.total = 0, this.open = 0, this.drafts = 0});
  final int total;
  final int open;
  final int drafts;
}

class AssignmentPage {
  const AssignmentPage({required this.items, this.nextCursor});
  final List<Assignment> items;
  final String? nextCursor;
}
