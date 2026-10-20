import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import '../../../core/network/adaptive_refresh.dart';
import '../domain/entities.dart';
import '../domain/events_repository.dart';

class AnnouncementFeedState {
  const AnnouncementFeedState({
    this.items = const [],
    this.loading = true,
    this.loadingMore = false,
    this.hasMore = false,
    this.hasNewItems = false,
    this.error,
    this.moreError,
  });
  final List<SchoolEvent> items;
  final bool loading, loadingMore, hasMore, hasNewItems;
  final Object? error, moreError;
}

/// Keeps an older-page snapshot while new publications arrive at the head.
class AnnouncementFeedSession with WidgetsBindingObserver {
  AnnouncementFeedSession(
    this.repository, {
    Duration pollEvery = const Duration(seconds: 30),
    Duration progressEvery = const Duration(seconds: 2),
    double Function()? random,
  }) {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _head = AdaptiveRefresh(
      read: _readHead,
      fallbackEvery: pollEvery,
      random: random,
      foreground: _foreground,
    );
    _progress = AdaptiveRefresh(
      read: _readProgress,
      fallbackEvery: progressEvery,
      eventDelay: const Duration(seconds: 2),
      random: random,
      foreground: false,
    );
  }
  final EventsRepository repository;
  late final AdaptiveRefresh _head, _progress;
  final _changes = StreamController<AnnouncementFeedState>.broadcast();
  StreamSubscription<AnnouncementSignal>? _signals;
  AnnouncementFeedState state = const AnnouncementFeedState();
  List<SchoolEvent> _first = [], _older = [];
  final _versions = <String, AnnouncementDelivery?>{};
  String? _cursor;
  bool _more = false, _new = false, _loading = true, _loadingMore = false;
  bool _disposed = false, _started = false, _foreground = true, _reset = false;
  int _generation = 0;
  Object? _error, _moreError;
  Future<void>? _morePending;

  Stream<AnnouncementFeedState> watch() => Stream.multi((sink) {
        sink.add(state);
        final subscription = _changes.stream
            .listen(sink.add, onDone: sink.close, onError: sink.addError);
        sink.onCancel = subscription.cancel;
        if (!_started) {
          _started = true;
          WidgetsBinding.instance.addObserver(this);
          _signals = repository.watchInvalidations().listen(
            (signal) {
              switch (signal.kind) {
                case AnnouncementSignalKind.publication:
                  _head.notifyEvent();
                case AnnouncementSignalKind.progress:
                  _progress.notifyEvent();
                case AnnouncementSignalKind.connection:
                  _head.setRealtimeHealthy(signal.healthy);
                  _progress.setRealtimeHealthy(signal.healthy);
              }
            },
            onError: (Object _) {
              _head.setRealtimeHealthy(false);
              _progress.setRealtimeHealthy(false);
            },
          );
          unawaited(_head.refresh());
        }
      });

  List<SchoolEvent> get _items => [..._first, ..._older].map((event) {
        if (!_versions.containsKey(event.id)) return event;
        return SchoolEvent(
          id: event.id,
          title: event.title,
          description: event.description,
          date: event.date,
          audience: event.audience,
          requestId: event.requestId,
          notificationWarning: event.notificationWarning,
          publicationError: event.publicationError,
          delivery: _versions[event.id],
        );
      }).toList();

  void _remember(SchoolEvent event) {
    final previous = _versions[event.id], incoming = event.delivery;
    if (!_versions.containsKey(event.id) ||
        previous?.updatedAt == null ||
        (incoming?.updatedAt != null &&
            !incoming!.updatedAt!.isBefore(previous!.updatedAt!))) {
      _versions[event.id] = incoming;
    }
  }

  void _emit() {
    if (_disposed) return;
    state = AnnouncementFeedState(
      items: List.unmodifiable(_items),
      loading: _loading,
      loadingMore: _loadingMore,
      hasMore: _more,
      hasNewItems: _new,
      error: _error,
      moreError: _moreError,
    );
    _changes.add(state);
    _syncProgress();
  }

  List<String> get _activeIds => _items
      .where(
        (e) => (e.delivery?.active ?? false) && RegExp(r'^\d+$').hasMatch(e.id),
      )
      .map((e) => e.id)
      .toList();
  void _syncProgress() =>
      _progress.setForeground(_foreground && _activeIds.isNotEmpty);

  Future<void> reload() async {
    _generation++;
    _loadingMore = false;
    _morePending = null;
    _reset = true;
    await _head.refresh();
    if (!_disposed && _foreground && _reset) await _head.refresh();
  }

  Future<void> _readHead() async {
    final generation = _generation, reset = _reset;
    _loading = true;
    _error = null;
    _emit();
    try {
      final page = await repository.publishedPage();
      if (_disposed || generation != _generation || !_foreground) return;
      for (final event in page.items) {
        _remember(event);
      }
      final changed = !listEquals(
        _first.map((e) => e.id).toList(),
        page.items.map((e) => e.id).toList(),
      );
      if (!reset && _older.isNotEmpty && changed) {
        _new = true;
      } else {
        _first = page.items;
        if (reset) {
          _older = [];
          _versions.removeWhere((id, _) => !_first.any((e) => e.id == id));
        }
        if (_older.isEmpty) {
          _cursor = page.nextBeforeId;
          _more = page.hasMore;
        }
        _new = false;
        _reset = false;
      }
    } catch (error) {
      if (!_disposed && generation == _generation) _error = error;
      rethrow;
    } finally {
      if (!_disposed && generation == _generation) {
        _loading = false;
        _emit();
      }
    }
  }

  Future<void> loadMore() {
    if (_morePending != null) return _morePending!;
    if (_disposed || !_foreground || !_more || _cursor == null) {
      return Future.value();
    }
    final pending = _readMore();
    _morePending = pending;
    return pending.whenComplete(() {
      if (identical(_morePending, pending)) _morePending = null;
    });
  }

  Future<void> _readMore() async {
    final generation = _generation, cursor = _cursor;
    _loadingMore = true;
    _moreError = null;
    _emit();
    try {
      final page = await repository.publishedPage(beforeId: cursor);
      if (_disposed || generation != _generation || !_foreground) return;
      if (page.hasMore &&
          (page.nextBeforeId == null || page.nextBeforeId == cursor)) {
        throw StateError('No se pudo avanzar la página de anuncios.');
      }
      final ids = {..._first.map((e) => e.id), ..._older.map((e) => e.id)};
      for (final row in page.items) {
        _remember(row);
        if (ids.add(row.id)) _older.add(row);
      }
      _cursor = page.nextBeforeId;
      _more = page.hasMore;
    } catch (error) {
      if (!_disposed && generation == _generation) _moreError = error;
    } finally {
      if (!_disposed && generation == _generation) {
        _loadingMore = false;
        _emit();
      }
    }
  }

  Future<void> refreshProgress() async {
    await _progress.refresh();
  }

  Future<void> _readProgress() async {
    final generation = _generation, ids = _activeIds;
    if (ids.isEmpty) return;
    final data = await repository.progress(ids);
    if (_disposed || generation != _generation || !_foreground) return;
    for (final id in ids) {
      if (!data.containsKey(id)) continue;
      final previous = _versions[id], incoming = data[id];
      if (previous?.updatedAt != null &&
          incoming?.updatedAt != null &&
          incoming!.updatedAt!.isBefore(previous!.updatedAt!)) {
        continue;
      }
      _versions[id] = incoming;
    }
    _emit();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _head.setForeground(_foreground);
    _syncProgress();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    _head.dispose();
    _progress.dispose();
    unawaited(_signals?.cancel());
    unawaited(_changes.close());
  }
}
