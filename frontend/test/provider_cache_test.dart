import 'dart:async';

import 'package:educa360/core/network/provider_cache.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('disposed dependency chains never start another data request', () async {
    final dependency = Completer<int>();
    final scope = StateProvider((ref) => 0);
    var requests = 0;
    final provider = FutureProvider.autoDispose<int>((ref) {
      final identity = ref.watch(scope);
      return ref.cacheAfter(identity == 0 ? dependency.future : Future.value(2),
          (value) async {
        requests++;
        return value;
      });
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.listen(provider, (_, __) {});
    container.read(scope.notifier).state = 1;
    expect(await container.read(provider.future), 2);
    dependency.complete(1);
    await container.pump();
    expect(requests, 1);
  });
  test('UI cannot reuse previous data across dependency or permission reloads',
      () {
    const previous = AsyncData('private');
    final reload = const AsyncLoading<String>()
        .copyWithPrevious(previous, isRefresh: false);
    final refresh = const AsyncLoading<String>().copyWithPrevious(previous);
    expect(reload.scopedValue, isNull);
    expect(refresh.scopedValue, 'private');
    expect(
      AsyncError<String>(StateError('revoked'), StackTrace.current)
          .copyWithPrevious(previous)
          .scopedValue,
      isNull,
    );
  });
  test('retains pending reads across route removal and expires inactive data',
      () async {
    final pending = Completer<int>();
    var calls = 0;
    final provider = FutureProvider.autoDispose<int>((ref) {
      calls++;
      return ref.cacheFor(
        calls == 1 ? pending.future : Future.value(calls),
        ttl: const Duration(milliseconds: 50),
      );
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    var listener = container.listen(provider, (_, __) {});
    final first = container.read(provider.future);
    listener.close();
    await container.pump();
    listener = container.listen(provider, (_, __) {});
    pending.complete(1);
    expect(await first, 1);
    expect(await container.read(provider.future), 1);
    expect(calls, 1);
    listener.close();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await container.pump();
    expect(calls, 1); // No background traffic for inactive families.
    container.listen(provider, (_, __) {});
    expect(await container.read(provider.future), 2);
  });

  test('active expiry retains previous value during revalidation', () async {
    var calls = 0;
    final refresh = Completer<int>();
    final provider = FutureProvider.autoDispose<int>(
      (ref) => ref.cacheFor(
        ++calls == 1 ? Future.value(1) : refresh.future,
        ttl: const Duration(milliseconds: 50),
      ),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.listen(provider, (_, __) {});
    expect(await container.read(provider.future), 1);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final state = container.read(provider);
    expect(state.isRefreshing, isTrue);
    expect(state.valueOrNull, 1);
    expect(
      state.when(
        data: (v) => '$v',
        error: (_, __) => 'error',
        loading: () => 'skeleton',
      ),
      '1',
    );
    refresh.complete(2);
    expect(await container.read(provider.future), 2);
  });

  test(
      'scope changes discard old account/institution/role values and late results',
      () async {
    final scope = StateProvider((ref) => 'institution:7:user:A:student');
    final old = Completer<String>();
    final provider = FutureProvider.autoDispose<String>((ref) {
      final identity = ref.watch(scope);
      return ref.cacheFor(
        identity.endsWith('student') ? old.future : Future.value(identity),
      );
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.listen(provider, (_, __) {});
    container.read(scope.notifier).state = 'institution:8:user:B:teacher';
    expect(
      await container.read(provider.future),
      'institution:8:user:B:teacher',
    );
    old.complete('private data from A');
    await container.pump();
    expect(
      container.read(provider).requireValue,
      'institution:8:user:B:teacher',
    );
  });

  test('failed reads retry on navigation; invalidation targets one family',
      () async {
    final calls = <int, int>{};
    final provider = FutureProvider.autoDispose.family<int, int>((ref, id) {
      final count = calls.update(id, (v) => v + 1, ifAbsent: () => 1);
      return ref.cacheFor(
        id == 1 && count == 1
            ? Future<int>.error(StateError('offline'))
            : Future.value(count),
      );
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final listener = container.listen(provider(1), (_, __) {});
    await expectLater(container.read(provider(1).future), throwsStateError);
    listener.close();
    await container.pump();
    container.listen(provider(1), (_, __) {});
    container.listen(provider(2), (_, __) {});
    expect(await container.read(provider(1).future), 2);
    expect(await container.read(provider(2).future), 1);
    container.invalidate(provider(1));
    expect(await container.read(provider(1).future), 3);
    expect(await container.read(provider(2).future), 1);
  });
}
