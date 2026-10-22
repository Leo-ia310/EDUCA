import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A dependency reload can carry the previous account's value in AsyncValue.
/// Keep previous data only for refreshes within the same identity/access scope.
extension ScopedAsyncValue<T> on AsyncValue<T> {
  T? get scopedValue => isReloading || hasError ? null : valueOrNull;
}

/// In-memory Riverpod state only. Identity/access must remain watched
/// dependencies so a scope change destroys both the value and its timer.
extension QueryRetention on Ref {
  Future<T> cacheAfter<A, T>(
    Future<A> dependency,
    Future<T> Function(A value) load, {
    Duration ttl = const Duration(minutes: 1),
  }) {
    var disposed = false;
    onDispose(() => disposed = true);
    return cacheFor(
      () async {
        final value = await dependency;
        if (disposed) throw StateError('query_scope_changed');
        return load(value);
      }(),
      ttl: ttl,
    );
  }

  Future<T> cacheFor<T>(
    Future<T> request, {
    Duration ttl = const Duration(minutes: 1),
  }) async {
    final link = keepAlive();
    var disposed = false;
    var listening = true;
    Timer? timer;
    onCancel(() => listening = false);
    onResume(() => listening = true);
    onDispose(() {
      disposed = true;
      timer?.cancel();
    });
    try {
      final value = await request;
      if (!disposed) {
        timer = Timer(ttl, () {
          // Active consumers refresh with AsyncValue's previous value.
          // Inactive families expire without background network traffic.
          if (listening) invalidateSelf();
          link.close();
        });
      }
      return value;
    } catch (_) {
      link.close(); // Never retain failed requests across navigation.
      rethrow;
    }
  }
}
