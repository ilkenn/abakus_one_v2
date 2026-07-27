import 'feature_flags_service.dart';

class NoOpFeatureFlagsService implements FeatureFlagsService {
  NoOpFeatureFlagsService();

  bool _isInitialized = false;

  @override
  bool get isInitialized => _isInitialized;

  @override
  Future<void> initialize() async {
    _isInitialized = true;
  }

  @override
  bool isEnabled(String key, {bool defaultValue = false}) => defaultValue;

  @override
  String getString(String key, {String defaultValue = ''}) => defaultValue;

  @override
  int getInt(String key, {int defaultValue = 0}) => defaultValue;
}
