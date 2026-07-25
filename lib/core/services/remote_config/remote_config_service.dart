abstract interface class RemoteConfigService {
  Future<void> initialize();

  Future<bool> fetch();

  Future<bool> activate();

  Future<bool> fetchAndActivate();

  String getString(String key, {String defaultValue = ''});

  bool getBool(String key, {bool defaultValue = false});

  int getInt(String key, {int defaultValue = 0});

  double getDouble(String key, {double defaultValue = 0.0});

  T? getValue<T>(String key);
}
