/// A generic remote value/configuration source — parameter-shaped values
/// (a version string, a threshold, an operational flag), fetched from
/// wherever this project's chosen remote-config vendor stores them.
///
/// **Not** an application-facing "is this feature available" API. Boolean
/// product-feature decisions (loyalty, campaigns, reservations, delivery,
/// QR, custom bowl, ...) are owned exclusively by `FeatureFlagsService`
/// (`lib/core/services/feature_flags/`), which happens to be backed by
/// this service today via `RemoteConfigFeatureFlagsService` — but nothing
/// outside that one adapter should ever call [getBool] (or any other
/// method here) to answer a feature-availability question directly. See
/// `RemoteConfigFeatureFlagsService`'s doc comment for the full ownership
/// boundary between the two services.
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
