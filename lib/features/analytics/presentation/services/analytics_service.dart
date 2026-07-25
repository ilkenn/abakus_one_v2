import '../../domain/models/analytics_event_type.dart';

abstract interface class AnalyticsService {
  Future<void> logEvent(AnalyticsEventType event,
      {Map<String, Object?>? parameters});
  Future<void> setUserProperty(String name, String? value);
  Future<void> setUserId(String? userId);
  Future<void> clearUser();
}
