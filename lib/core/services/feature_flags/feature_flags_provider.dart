import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'feature_flags_service.dart';
import 'noop_feature_flags_service.dart';

final featureFlagsServiceProvider = Provider<FeatureFlagsService>((ref) {
  return const NoOpFeatureFlagsService();
});
