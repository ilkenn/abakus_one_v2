import 'package:firebase_remote_config/firebase_remote_config.dart'
    as firebase_remote_config;

/// Narrow seam over the real `firebase_remote_config` SDK, injected into
/// [FirebaseRemoteConfigService] so it's testable under `flutter test`
/// (no real Firebase app is available there) — same rationale as
/// `FirebaseBootstrapService`'s `FirebaseInitializer` typedef.
///
/// This is the **only** file, besides its own private
/// [_FirebaseRemoteConfigClient] implementation below, allowed to import
/// `package:firebase_remote_config` — everything else in
/// `FirebaseRemoteConfigService` talks to this abstraction instead,
/// keeping Firebase-specific knowledge isolated inside the
/// `remote_config/` folder as required.
abstract interface class RemoteConfigClient {
  Future<void> setConfigSettings({
    required Duration fetchTimeout,
    required Duration minimumFetchInterval,
  });

  Future<void> fetch();

  Future<bool> activate();

  Future<bool> fetchAndActivate();

  /// Whether [key] resolved to a fetched or SDK-side-default value, as
  /// opposed to the SDK's own type-zero fallback for a key it has never
  /// seen. [FirebaseRemoteConfigService] uses this to decide between
  /// returning the real value and the caller-supplied `defaultValue` —
  /// deliberately not relying on the SDK's own `setDefaults` mechanism, so
  /// there is exactly one place (the caller's `defaultValue` argument)
  /// that owns "what's safe if we don't know."
  bool hasValue(String key);

  bool getBool(String key);

  String getString(String key);

  int getInt(String key);

  double getDouble(String key);
}

/// The real [RemoteConfigClient], wrapping
/// `firebase_remote_config.FirebaseRemoteConfig`.
///
/// [_instance] is resolved lazily (on first actual use, not at
/// construction) — `FirebaseRemoteConfig.instance` requires an already-
/// initialized default [FirebaseApp], which only exists once
/// [FirebaseBootstrapService] has actually run. Resolving it eagerly here
/// would make constructing a [FirebaseRemoteConfigService] itself unsafe
/// before that point (e.g. while wiring providers in tests); deferring it
/// means construction is always safe, and only calling a method that
/// needs the SDK can fail.
class FirebaseRemoteConfigClient implements RemoteConfigClient {
  FirebaseRemoteConfigClient(
      [firebase_remote_config.FirebaseRemoteConfig? instance])
      : _providedInstance = instance;

  final firebase_remote_config.FirebaseRemoteConfig? _providedInstance;

  firebase_remote_config.FirebaseRemoteConfig get _instance =>
      _providedInstance ?? firebase_remote_config.FirebaseRemoteConfig.instance;

  @override
  Future<void> setConfigSettings({
    required Duration fetchTimeout,
    required Duration minimumFetchInterval,
  }) {
    return _instance.setConfigSettings(
      firebase_remote_config.RemoteConfigSettings(
        fetchTimeout: fetchTimeout,
        minimumFetchInterval: minimumFetchInterval,
      ),
    );
  }

  @override
  Future<void> fetch() => _instance.fetch();

  @override
  Future<bool> activate() => _instance.activate();

  @override
  Future<bool> fetchAndActivate() => _instance.fetchAndActivate();

  @override
  bool hasValue(String key) {
    return _instance.getValue(key).source !=
        firebase_remote_config.ValueSource.valueStatic;
  }

  @override
  bool getBool(String key) => _instance.getBool(key);

  @override
  String getString(String key) => _instance.getString(key);

  @override
  int getInt(String key) => _instance.getInt(key);

  @override
  double getDouble(String key) => _instance.getDouble(key);
}
