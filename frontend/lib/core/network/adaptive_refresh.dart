import 'dart:async';
import 'dart:math';

/// One refresh at a time, with a trailing refresh when an event arrives during
/// a read. Realtime is primary; polling reconciles healthy channels infrequently.
/// The owning repository supplies foreground/background lifecycle changes.
class AdaptiveRefresh {
  AdaptiveRefresh({
    required Future<void> Function() read,
    this.fallbackEvery = const Duration(seconds: 30),
    this.reconcileEvery = const Duration(minutes: 5),
    this.maxBackoff = const Duration(minutes: 5),
    this.eventDelay = const Duration(milliseconds: 150),
    this.coalesceEvents = false,
    double Function()? random,
    bool foreground = true,
  })  : assert(fallbackEvery > Duration.zero),
        assert(reconcileEvery > Duration.zero),
        assert(maxBackoff > Duration.zero),
        assert(eventDelay >= Duration.zero),
        _read = read,
        _random = random ?? Random().nextDouble,
        _foreground = foreground;

  final bool coalesceEvents;
  final Future<void> Function() _read;
  final double Function() _random;
  final Duration fallbackEvery, reconcileEvery, maxBackoff, eventDelay;
  Timer? _poll, _events;
  Future<bool>? _pending;
  bool _foreground, _healthy = false, _disposed = false, _trailing = false;
  int _failures = 0;

  void start() => _schedule();

  Future<bool> refresh() {
    if (_disposed || !_foreground) return Future.value(false);
    if (_pending != null) return _pending!;
    _poll?.cancel();
    _pending = _run();
    return _pending!;
  }

  Future<bool> _run() async {
    var success = false;
    try {
      await Future<void>.sync(_read);
      _failures = 0;
      success = true;
    } catch (_) {
      _failures = min(_failures + 1, 20);
    } finally {
      _pending = null;
      _schedule();
      if (_trailing) {
        _trailing = false;
        notifyEvent();
      }
    }
    return success;
  }

  void notifyEvent() {
    if (_disposed || !_foreground) return;
    if (_pending != null) {
      _trailing = true;
      return;
    }
    if (coalesceEvents && (_events?.isActive ?? false)) return;
    _events?.cancel();
    _events = Timer(eventDelay, () { _events = null; unawaited(refresh()); });
  }

  void setRealtimeHealthy(bool healthy) {
    if (_healthy == healthy || _disposed) return;
    _healthy = healthy;
    _schedule();
  }

  void setForeground(bool foreground) {
    if (_foreground == foreground || _disposed) return;
    _foreground = foreground;
    _poll?.cancel();
    _events?.cancel();
    _trailing = false;
    if (foreground) {
      _trailing = _pending != null;
      unawaited(refresh());
    }
  }

  void _schedule() {
    _poll?.cancel();
    if (_disposed || !_foreground) return;
    final base = _healthy && _failures == 0 ? reconcileEvery : fallbackEvery;
    final multiplier = 1 << min(_failures, 10);
    final milliseconds =
        (min(base.inMilliseconds * multiplier, maxBackoff.inMilliseconds) *
                (0.8 + _random().clamp(0, 1) * 0.4))
            .round()
            .clamp(1, maxBackoff.inMilliseconds);
    _poll =
        Timer(Duration(milliseconds: milliseconds), () => unawaited(refresh()));
  }

  void dispose() {
    _disposed = true;
    _trailing = false;
    _poll?.cancel();
    _events?.cancel();
  }
}
