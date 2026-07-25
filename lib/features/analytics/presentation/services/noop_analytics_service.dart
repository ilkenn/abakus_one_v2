import '../../domain/models/analytics_event_type.dart';
import 'analytics_service.dart';

class NoOpAnalyticsService implements AnalyticsService {
  const NoOpAnalyticsService();

  @override
  Future<void> logEvent(AnalyticsEventType event,
      {Map<String, Object?>? parameters}) async {
    // No-op implementation for testing and initial development.
  }

  @override
  Future<void> setUserProperty(String name, String? value) async {
    // No-op implementation.
  }

  @override
  Future<void> setUserId(String? userId) async {
    // No-op implementation.
  }

  @override
  Future<void> clearUser() async {
    // No-op implementation.
  }
}
