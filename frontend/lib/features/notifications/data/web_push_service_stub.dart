import 'package:educa360/core/network/backend_api_client.dart';

import '../domain/entities.dart';
import '../domain/push_service.dart';
import 'demo_push_service.dart';

class WebPushService implements PushService {
  WebPushService({required BackendApiClient api, required String userId})
      : _delegate = DemoPushService();

  final DemoPushService _delegate;

  @override
  Future<void> init() => _delegate.init();

  @override
  Future<String?> deviceToken() => _delegate.deviceToken();

  @override
  Stream<AppNotification> get incoming => _delegate.incoming;

  @override
  Stream<AppNotification> get onTap => _delegate.onTap;

  @override
  Future<void> subscribeToTopic(String topic) =>
      _delegate.subscribeToTopic(topic);

  @override
  Future<void> unsubscribeFromTopic(String topic) =>
      _delegate.unsubscribeFromTopic(topic);

  @override
  Future<void> simulate(AppNotification n) => _delegate.simulate(n);
}
