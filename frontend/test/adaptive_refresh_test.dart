import 'dart:async';
import 'package:educa360/core/network/adaptive_refresh.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('continuous progress events refresh within a fixed coalescing window', (tester) async {
    var calls = 0;
    final driver = AdaptiveRefresh(read: () async { calls++; },
      coalesceEvents: true, eventDelay: const Duration(seconds: 2), random: () => .5,
    );
    driver.setRealtimeHealthy(true);
    for (var i = 0; i < 4; i++) {
      driver.notifyEvent();
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(calls, 1);
    driver.dispose();
  });
  testWidgets(
      'coalesces reads and event bursts, then reconciles healthy realtime infrequently',
      (tester) async {
    var calls = 0;
    final pending = Completer<void>();
    final driver = AdaptiveRefresh(
        read: () {
          calls++;
          return calls == 1 ? pending.future : Future<void>.value();
        },
        random: () => 0.5,);
    addTearDown(driver.dispose);
    final a = driver.refresh(), b = driver.refresh();
    expect(identical(a, b), isTrue);
    expect(calls, 1);
    driver.notifyEvent();
    driver.notifyEvent();
    driver.notifyEvent();
    pending.complete();
    await tester.pump();
    expect(calls, 1);
    await tester.pump(const Duration(milliseconds: 150));
    expect(calls, 2);
    driver.setRealtimeHealthy(true);
    await tester.pump(const Duration(minutes: 4));
    expect(calls, 2);
    await tester.pump(const Duration(minutes: 1));
    expect(calls, 3);
    driver.dispose();
    await tester.pump(const Duration(minutes: 10));
    expect(calls, 3);
  });

  testWidgets(
      'failed reads back off and foreground resume recovers immediately',
      (tester) async {
    var calls = 0, fail = true;
    final driver = AdaptiveRefresh(
        read: () {
          calls++;
          if (fail) throw StateError('offline');
          return Future<void>.value();
        },
        fallbackEvery: const Duration(seconds: 1),
        maxBackoff: const Duration(seconds: 8),
        random: () => 0.5,);
    addTearDown(driver.dispose);
    unawaited(driver.refresh());
    await tester.pump();
    expect(calls, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 2);
    await tester.pump(const Duration(seconds: 4));
    expect(calls, 3);
    driver.setForeground(false);
    driver.notifyEvent();
    await tester.pump(const Duration(minutes: 1));
    expect(calls, 3);
    fail = false;
    driver.setForeground(true);
    await tester.pump();
    expect(calls, 4);
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 5);
    driver.dispose();
    await tester.pump(const Duration(minutes: 1));
    expect(calls, 5);
  });

  testWidgets(
      'resume during an in-flight request schedules a fresh read; disposal drops trailing work',
      (tester) async {
    var calls = 0;
    final pending = Completer<void>();
    final driver = AdaptiveRefresh(
        read: () {
          calls++;
          return calls == 1 ? pending.future : Future<void>.value();
        },
        random: () => 0.5,);
    unawaited(driver.refresh());
    driver.setForeground(false);
    driver.notifyEvent();
    driver.setForeground(true);
    pending.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(calls, 2);
    driver.notifyEvent();
    driver.dispose();
    await tester.pump(const Duration(minutes: 10));
    expect(calls, 2);
  });
}
