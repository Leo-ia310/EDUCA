import 'dart:async';

import 'package:educa360/features/chat/presentation/controllers/conversation_read_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('arrivals during a pending read are confirmed in a second request',
      () async {
    final first = Completer<void>();
    var calls = 0;
    var refreshed = 0;
    final tracker = ConversationReadTracker(
      markRead: () async {
        calls++;
        if (calls == 1) await first.future;
      },
      refreshAlerts: () async {
        refreshed++;
      },
    );
    final pending = tracker.read();
    final queued = tracker.read();
    expect(calls, 1);
    first.complete();
    await Future.wait([pending, queued]);
    expect(calls, 2);
    expect(refreshed, 2);
  });

  test('failed reads remain retryable and do not refresh alerts as if read',
      () async {
    var fail = true;
    var refreshed = 0;
    final tracker = ConversationReadTracker(
      markRead: () async {
        if (fail) throw StateError('offline');
      },
      refreshAlerts: () async {
        refreshed++;
      },
    );
    await expectLater(tracker.read(), throwsStateError);
    expect(refreshed, 0);
    fail = false;
    await tracker.read();
    expect(refreshed, 1);
  });
}
