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

class AssignmentPage {
  const AssignmentPage({required this.items, this.nextCursor});
  final List<Assignment> items;
  final String? nextCursor;
}
