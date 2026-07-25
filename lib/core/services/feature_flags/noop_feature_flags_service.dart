import 'feature_flags_service.dart';

class NoOpFeatureFlagsService implements FeatureFlagsService {
  const NoOpFeatureFlagsService();

  @override
  Future<void> initialize() async {}

  @override
  bool isEnabled(String key, {bool defaultValue = false}) => defaultValue;
}
