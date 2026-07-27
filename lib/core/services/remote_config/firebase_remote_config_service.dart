import '../../../bootstrap/app_environment.dart';
import '../../errors/error_mapper.dart';
import '../logging/log_level.dart';
import '../logging/logging_service.dart';
import 'remote_config_client.dart';
import 'remote_config_fetch_policy.dart';
import 'remote_config_service.dart';

/// The real, Firebase-backed [RemoteConfigService].
///
/// All knowledge of the `firebase_remote_config` package is isolated to
/// this file and [RemoteConfigClient] (its injected SDK seam) — nothing
/// above [RemoteConfigService] (in particular
/// `RemoteConfigFeatureFlagsService`) ever needs to know Firebase is
/// involved.
///
/// Every public method here follows [FirebaseBootstrapService]'s
/// established shape: catch everything, map through [ErrorMapper], log via
/// [LoggingService] (never a raw exception), and return a safe fallback —
/// never throw. This is what makes "Remote Config failure must not prevent
/// application startup" true structurally, not just by convention.
class FirebaseRemoteConfigService implements RemoteConfigService {
  FirebaseRemoteConfigService({
    required AppEnvironment environment,
    required LoggingService loggingService,
    RemoteConfigClient? client,
  })  : _environment = environment,
        _loggingService = loggingService,
        _client = client ?? FirebaseRemoteConfigClient();

  final AppEnvironment _environment;
  final LoggingService _loggingService;
  final RemoteConfigClient _client;

  @override
  Future<void> initialize() async {
    try {
      final policy = RemoteConfigFetchPolicy.forEnvironment(_environment);
      await _client.setConfigSettings(
        fetchTimeout: policy.fetchTimeout,
        minimumFetchInterval: policy.minimumFetchInterval,
      );
      await _client.fetchAndActivate();
    } catch (error, stackTrace) {
      // Never rethrown: an environment with no network, a disabled Remote
      // Config API, or any other startup-time failure must still let the
      // app boot — every getter below falls back to the caller's
      // defaultValue when nothing was ever successfully fetched.
      _logFailure('Remote Config initialization failed', error, stackTrace);
    }
  }

  @override
  Future<bool> fetch() async {
    try {
      await _client.fetch();
      return true;
    } catch (error, stackTrace) {
      _logFailure('Remote Config fetch failed', error, stackTrace);
      return false;
    }
  }

  @override
  Future<bool> activate() async {
    try {
      return await _client.activate();
    } catch (error, stackTrace) {
      _logFailure('Remote Config activate failed', error, stackTrace);
      return false;
    }
  }

  @override
  Future<bool> fetchAndActivate() async {
    try {
      return await _client.fetchAndActivate();
    } catch (error, stackTrace) {
      _logFailure('Remote Config fetchAndActivate failed', error, stackTrace);
      return false;
    }
  }

  @override
  bool getBool(String key, {bool defaultValue = false}) {
    if (!_client.hasValue(key)) return defaultValue;
    return _client.getBool(key);
  }

  @override
  String getString(String key, {String defaultValue = ''}) {
    if (!_client.hasValue(key)) return defaultValue;
    return _client.getString(key);
  }

  @override
  int getInt(String key, {int defaultValue = 0}) {
    if (!_client.hasValue(key)) return defaultValue;
    return _client.getInt(key);
  }

  @override
  double getDouble(String key, {double defaultValue = 0.0}) {
    if (!_client.hasValue(key)) return defaultValue;
    return _client.getDouble(key);
  }

  @override
  T? getValue<T>(String key) {
    if (!_client.hasValue(key)) return null;
    if (T == bool) return _client.getBool(key) as T;
    if (T == String) return _client.getString(key) as T;
    if (T == int) return _client.getInt(key) as T;
    if (T == double) return _client.getDouble(key) as T;
    return null;
  }

  void _logFailure(String message, Object error, StackTrace stackTrace) {
    final failure = ErrorMapper.map(error);
    _loggingService.log(
      LogLevel.error,
      '$message: ${failure.message}',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
