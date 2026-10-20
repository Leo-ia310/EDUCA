/// Complete domain grids/exports through bounded requests. Queries must have
/// deterministic ordering, including a unique tie breaker. A server may cap
/// responses below the requested size, so only an empty page ends the scan.
Future<List<T>> readAllPages<T>(
  Future<List<T>> Function(int from, int to) fetch,
) async {
  final rows = <T>[];
  const size = 500;
  while (true) {
    final page = await fetch(rows.length, rows.length + size - 1);
    if (page.isEmpty) return rows;
    rows.addAll(page);
  }
}
