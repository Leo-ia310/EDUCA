import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The shared Supabase socket carries only a revision, never permission data.
/// Multiple settings changed together produce a single coalesced refresh.
class PortalAccessSync with WidgetsBindingObserver {
  PortalAccessSync({
    required SupabaseClient client,
    required int institutionId,
    required VoidCallback onChange,
  })  : _client = client,
        _onChange = onChange {
    WidgetsBinding.instance.addObserver(this);
    _channel = client
        .channel('portal-access:$institutionId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'portal_access_revisions',
          filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'institution_id',
              value: institutionId,),
          callback: (_) => _changed(),
        )
        .subscribe((status, _) {
      if (status == RealtimeSubscribeStatus.subscribed) {
        if (_subscribedOnce) _changed();
        _subscribedOnce = true;
      }
    });
  }
  final SupabaseClient _client;
  final VoidCallback _onChange;
  RealtimeChannel? _channel;
  Timer? _debounce;
  bool _subscribedOnce = false, _disposed = false;
  void _changed() {
    if (_disposed) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!_disposed) _onChange();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _changed();
  }

  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    final channel = _channel;
    if (channel != null) unawaited(_client.removeChannel(channel));
  }
}
