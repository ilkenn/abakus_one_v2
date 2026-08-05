import 'package:abakus_one_v2/core/services/crash_reporting/firebase_crashlytics_service.dart';
import 'package:abakus_one_v2/core/services/logging/log_level.dart';
import 'package:abakus_one_v2/core/services/logging/logging_service.dart';
import 'package:flutter/foundation.dart';
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

class _RecordingCrashlyticsClient implements CrashlyticsClient {
  Object? lastError;
  StackTrace? lastStackTrace;
  dynamic lastReason;
  Iterable<Object> lastInformation = const [];
  bool? lastErrorFatal;
  final List<String> loggedMessages = [];
  String? lastUserIdentifier;
  final Map<String, Object> customKeys = {};
  bool? collectionEnabled;
  bool throwOnCall = false;

  @override
  Future<void> recordError(
    dynamic exception,
    StackTrace? stack, {
    dynamic reason,
    Iterable<Object> information = const [],
    bool? fatal,
    bool printDetails = true,
  }) async {
    if (throwOnCall) throw Exception('recordError failed');
    lastError = exception;
    lastStackTrace = stack;
    lastReason = reason;
    lastInformation = information;
    lastErrorFatal = fatal;
  }

  @override
  Future<void> recordFlutterError(FlutterErrorDetails details,
      {bool? fatal}) async {
    if (throwOnCall) throw Exception('recordFlutterError failed');
  }

  @override
  Future<void> log(String message) async {
    if (throwOnCall) throw Exception('log failed');
    loggedMessages.add(message);
  }

  @override
  Future<void> setUserIdentifier(String identifier) async {
    if (throwOnCall) throw Exception('setUserIdentifier failed');
    lastUserIdentifier = identifier;
  }

  @override
  Future<void> setCustomKey(String key, Object value) async {
    if (throwOnCall) throw Exception('setCustomKey failed');
    customKeys[key] = value;
  }

  @override
  Future<void> setCrashlyticsCollectionEnabled(bool enabled) async {
    if (throwOnCall) throw Exception('setCrashlyticsCollectionEnabled failed');
    collectionEnabled = enabled;
  }
}

void main() {
  // kIsWeb is a compile-time constant, false under this suite's default VM
  // test run — the "web is unsupported" branch can't be exercised here,
  // mirroring FirebaseAppCheckService's own documented Web-test limitation.

  group('FirebaseCrashlyticsService.initialize', () {
    test('development (debug tooling allowed) disables collection', () async {
      final client = _RecordingCrashlyticsClient();
      final service = FirebaseCrashlyticsService(
        allowsDebugTooling: true,
        loggingService: _RecordingLoggingService(),
        client: client,
      );

      await service.initialize();

      expect(client.collectionEnabled, isFalse);
    });

    test('production (debug tooling not allowed) enables collection', () async {
      final client = _RecordingCrashlyticsClient();
      final service = FirebaseCrashlyticsService(
        allowsDebugTooling: false,
        loggingService: _RecordingLoggingService(),
        client: client,
      );

      await service.initialize();

      expect(client.collectionEnabled, isTrue);
    });

    test('never throws when the underlying activation fails', () async {
      final client = _RecordingCrashlyticsClient()..throwOnCall = true;
      final logger = _RecordingLoggingService();
      final service = FirebaseCrashlyticsService(
        allowsDebugTooling: false,
        loggingService: logger,
        client: client,
      );

      await expectLater(service.initialize(), completes);
      expect(logger.levels, contains(LogLevel.error));
    });
  });

  group('FirebaseCrashlyticsService.recordError', () {
    test('forwards the error and stack trace unchanged', () async {
      final client = _RecordingCrashlyticsClient();
      final service = FirebaseCrashlyticsService(
        allowsDebugTooling: false,
        loggingService: _RecordingLoggingService(),
        client: client,
      );
      final error = Exception('boom');
      final stackTrace = StackTrace.current;

      await service.recordError(error, stackTrace: stackTrace, fatal: true);

      expect(client.lastError, error);
      expect(client.lastStackTrace, stackTrace);
      expect(client.lastErrorFatal, isTrue);
    });

    test(
        'redacts sensitive context keys before forwarding — never leaks a '
        'real token to the vendor', () async {
      final client = _RecordingCrashlyticsClient();
      final service = FirebaseCrashlyticsService(
        allowsDebugTooling: false,
        loggingService: _RecordingLoggingService(),
        client: client,
      );

      await service.recordError(
        Exception('boom'),
        context: {'authToken': 'super-secret-value', 'screen': 'checkout'},
      );

      final joined = client.lastInformation.join();
      expect(joined.contains('super-secret-value'), isFalse);
      expect(joined.contains('checkout'), isTrue);
    });

    test('sanitizes a reason string before forwarding', () async {
      final client = _RecordingCrashlyticsClient();
      final service = FirebaseCrashlyticsService(
        allowsDebugTooling: false,
        loggingService: _RecordingLoggingService(),
        client: client,
      );

      await service.recordError(
        Exception('boom'),
        reason: 'failed for user someone@example.com',
      );

      expect(client.lastReason, isNot(contains('someone@example.com')));
    });

    test('never throws when the underlying client fails', () async {
      final client = _RecordingCrashlyticsClient()..throwOnCall = true;
      final service = FirebaseCrashlyticsService(
        allowsDebugTooling: false,
        loggingService: _RecordingLoggingService(),
        client: client,
      );

      await expectLater(service.recordError(Exception('boom')), completes);
    });
  });

  group('FirebaseCrashlyticsService.log', () {
    test('sanitizes the message before forwarding', () async {
      final client = _RecordingCrashlyticsClient();
      final service = FirebaseCrashlyticsService(
        allowsDebugTooling: false,
        loggingService: _RecordingLoggingService(),
        client: client,
      );

      await service.log('otp=123456 failed to verify');

      expect(client.loggedMessages.single.contains('123456'), isFalse);
    });
  });

  group('FirebaseCrashlyticsService.setCustomKey', () {
    test('redacts a sensitive key\'s value before forwarding', () async {
      final client = _RecordingCrashlyticsClient();
      final service = FirebaseCrashlyticsService(
        allowsDebugTooling: false,
        loggingService: _RecordingLoggingService(),
        client: client,
      );

      await service.setCustomKey('password', 'hunter2');

      expect(client.customKeys['password'], isNot('hunter2'));
    });

    test('passes a non-sensitive key\'s value through unchanged', () async {
      final client = _RecordingCrashlyticsClient();
      final service = FirebaseCrashlyticsService(
        allowsDebugTooling: false,
        loggingService: _RecordingLoggingService(),
        client: client,
      );

      await service.setCustomKey('branchId', 'branch-1');

      expect(client.customKeys['branchId'], 'branch-1');
    });
  });

  group('FirebaseCrashlyticsService.setUserIdentifier', () {
    test('forwards the identifier', () async {
      final client = _RecordingCrashlyticsClient();
      final service = FirebaseCrashlyticsService(
        allowsDebugTooling: false,
        loggingService: _RecordingLoggingService(),
        client: client,
      );

      await service.setUserIdentifier('platform-uid-1');

      expect(client.lastUserIdentifier, 'platform-uid-1');
    });
  });
}
