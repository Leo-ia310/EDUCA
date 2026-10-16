/// Coalesces arrivals while a read request is in flight. A later arrival must
/// trigger another request because it may be newer than the server snapshot.
class ConversationReadTracker {
  ConversationReadTracker({
    required this.markRead,
    required this.refreshAlerts,
  });

  final Future<void> Function() markRead;
  final Future<void> Function() refreshAlerts;
  Future<void>? _running;
  bool _pending = false;

  Future<void> read() {
    _pending = true;
    return _running ??= _drain().whenComplete(() => _running = null);
  }

  Future<void> _drain() async {
    while (_pending) {
      _pending = false;
      await markRead();
      await refreshAlerts();
    }
  }
}
