import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/analytics_service.dart';
import '../services/noop_analytics_service.dart';

final analyticsServiceProvider = Provider<AnalyticsService>((ref) {
  return const NoOpAnalyticsService();
});
