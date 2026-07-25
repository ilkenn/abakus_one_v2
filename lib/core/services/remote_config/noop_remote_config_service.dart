import 'remote_config_service.dart';

class NoOpRemoteConfigService implements RemoteConfigService {
  const NoOpRemoteConfigService();

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> fetch() async => true;

  @override
  Future<bool> activate() async => true;

  @override
  Future<bool> fetchAndActivate() async => true;

  @override
  String getString(String key, {String defaultValue = ''}) => defaultValue;

  @override
  bool getBool(String key, {bool defaultValue = false}) => defaultValue;

  @override
  int getInt(String key, {int defaultValue = 0}) => defaultValue;

  @override
  double getDouble(String key, {double defaultValue = 0.0}) => defaultValue;

  @override
  T? getValue<T>(String key) => null;
}
