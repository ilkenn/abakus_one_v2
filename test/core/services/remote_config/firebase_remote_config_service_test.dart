import 'package:abakus_one_v2/bootstrap/app_environment.dart';
import 'package:abakus_one_v2/core/services/logging/log_level.dart';
import 'package:abakus_one_v2/core/services/logging/logging_service.dart';
import 'package:abakus_one_v2/core/services/remote_config/firebase_remote_config_service.dart';
import 'package:abakus_one_v2/core/services/remote_config/remote_config_client.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingLoggingService implements LoggingService {
  final List<LogLevel> levels = [];
  final List<String> messages = [];

  @override
  void log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? context,
  }) {
    levels.add(level);
    messages.add(message);
  }
}

class _FakeRemoteConfigClient implements RemoteConfigClient {
  bool throwOnSetConfigSettings = false;
  bool throwOnFetch = false;
  bool throwOnActivate = false;
  bool throwOnFetchAndActivate = false;

  Duration? capturedFetchTimeout;
  Duration? capturedMinimumFetchInterval;
  int fetchAndActivateCallCount = 0;

  final Map<String, bool> _boolValues = {};
  final Set<String> _knownKeys = {};

  void seedBool(String key, bool value) {
    _boolValues[key] = value;
    _knownKeys.add(key);
  }

  @override
  Future<void> setConfigSettings({
    required Duration fetchTimeout,
    required Duration minimumFetchInterval,
  }) async {
    if (throwOnSetConfigSettings) throw Exception('setConfigSettings failed');
    capturedFetchTimeout = fetchTimeout;
    capturedMinimumFetchInterval = minimumFetchInterval;
  }

  @override
  Future<void> fetch() async {
    if (throwOnFetch) throw Exception('fetch failed');
  }

  @override
  Future<bool> activate() async {
    if (throwOnActivate) throw Exception('activate failed');
    return true;
  }

  @override
  Future<bool> fetchAndActivate() async {
    fetchAndActivateCallCount++;
    if (throwOnFetchAndActivate) throw Exception('fetchAndActivate failed');
    return true;
  }

  @override
  bool hasValue(String key) => _knownKeys.contains(key);

  @override
  bool getBool(String key) => _boolValues[key] ?? false;

  @override
  String getString(String key) => '';

  @override
  int getInt(String key) => 0;

  @override
  double getDouble(String key) => 0.0;
}

void main() {
  group('FirebaseRemoteConfigService.initialize', () {
    test('applies the environment fetch policy and fetches/activates',
        () async {
      final client = _FakeRemoteConfigClient();
      final service = FirebaseRemoteConfigService(
        environment: AppEnvironment.development,
        loggingService: _RecordingLoggingService(),
        client: client,
      );

      await service.initialize();

      expect(client.capturedMinimumFetchInterval, const Duration(minutes: 1));
      expect(client.fetchAndActivateCallCount, 1);
    });

    test('never throws when setConfigSettings fails', () async {
      final client = _FakeRemoteConfigClient()..throwOnSetConfigSettings = true;
      final logger = _RecordingLoggingService();
      final service = FirebaseRemoteConfigService(
        environment: AppEnvironment.production,
        loggingService: logger,
        client: client,
      );

      await expectLater(service.initialize(), completes);
      expect(logger.levels, [LogLevel.error]);
    });

    test('never throws when fetchAndActivate fails', () async {
      final client = _FakeRemoteConfigClient()..throwOnFetchAndActivate = true;
      final logger = _RecordingLoggingService();
      final service = FirebaseRemoteConfigService(
        environment: AppEnvironment.production,
        loggingService: logger,
        client: client,
      );

      await expectLater(service.initialize(), completes);
      expect(logger.levels, [LogLevel.error]);
    });
  });

  group('FirebaseRemoteConfigService getters', () {
    test('getBool returns defaultValue when the client has never seen the key',
        () {
      final client = _FakeRemoteConfigClient();
      final service = FirebaseRemoteConfigService(
        environment: AppEnvironment.development,
        loggingService: _RecordingLoggingService(),
        client: client,
      );

      expect(service.getBool('unknown_key'), isFalse);
      expect(service.getBool('unknown_key', defaultValue: true), isTrue);
    });

    test('getBool returns the fetched value once the client has it', () {
      final client = _FakeRemoteConfigClient()
        ..seedBool('otp_login_enabled', true);
      final service = FirebaseRemoteConfigService(
        environment: AppEnvironment.development,
        loggingService: _RecordingLoggingService(),
        client: client,
      );

      expect(
        service.getBool('otp_login_enabled', defaultValue: false),
        isTrue,
      );
    });

    test('getValue<bool> mirrors getBool once fetched, null otherwise', () {
      final client = _FakeRemoteConfigClient()
        ..seedBool('otp_login_enabled', true);
      final service = FirebaseRemoteConfigService(
        environment: AppEnvironment.development,
        loggingService: _RecordingLoggingService(),
        client: client,
      );

      expect(service.getValue<bool>('unknown_key'), isNull);
      expect(service.getValue<bool>('otp_login_enabled'), isTrue);
    });
  });

  group('FirebaseRemoteConfigService fetch/activate/fetchAndActivate', () {
    test('fetch returns false (never throws) on failure', () async {
      final client = _FakeRemoteConfigClient()..throwOnFetch = true;
      final service = FirebaseRemoteConfigService(
        environment: AppEnvironment.development,
        loggingService: _RecordingLoggingService(),
        client: client,
      );

      expect(await service.fetch(), isFalse);
    });

    test('activate returns false (never throws) on failure', () async {
      final client = _FakeRemoteConfigClient()..throwOnActivate = true;
      final service = FirebaseRemoteConfigService(
        environment: AppEnvironment.development,
        loggingService: _RecordingLoggingService(),
        client: client,
      );

      expect(await service.activate(), isFalse);
    });

    test('fetchAndActivate returns false (never throws) on failure', () async {
      final client = _FakeRemoteConfigClient()..throwOnFetchAndActivate = true;
      final service = FirebaseRemoteConfigService(
        environment: AppEnvironment.development,
        loggingService: _RecordingLoggingService(),
        client: client,
      );

      expect(await service.fetchAndActivate(), isFalse);
    });
  });
}
