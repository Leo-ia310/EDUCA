import 'package:educa360/core/network/read_all.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads all 1207 rows even when server caps requested pages to 100',
      () async {
    final source = List.generate(1207, (i) => i), offsets = <int>[];
    final rows = await readAllPages<int>((from, to) async {
      offsets.add(from);
      final end = (from + 100).clamp(0, source.length);
      return source.sublist(from, end);
    });
    expect(rows, source);
    expect(offsets[1], 100);
    expect(offsets.last, 1207);
  });
  test('later page error does not return partial data', () async {
    await expectLater(readAllPages<int>((from, to) async {
      if (from > 0) throw StateError('Page failed');
      return [1];
    }), throwsStateError,);
  });
}
