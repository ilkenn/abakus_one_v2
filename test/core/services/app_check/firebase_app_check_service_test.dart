import 'package:abakus_one_v2/core/services/app_check/firebase_app_check_service.dart';
import 'package:abakus_one_v2/core/services/logging/log_level.dart';
import 'package:abakus_one_v2/core/services/logging/logging_service.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
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

class _RecordingActivation {
  AndroidAppCheckProvider? providerAndroid;
  AppleAppCheckProvider? providerApple;
  WebProvider? providerWeb;
  WindowsAppCheckProvider? providerWindows;
  int callCount = 0;
}

void main() {
  setUp(() {
    debugDefaultTargetPlatformOverride = null;
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  group('FirebaseAppCheckService — Android', () {
    test('development activates the debug provider', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final recorded = _RecordingActivation();
      final service = FirebaseAppCheckService(
        allowsDebugTooling: true,
        loggingService: _RecordingLoggingService(),
        activate: (
            {providerAndroid,
            providerApple,
            providerWeb,
            providerWindows}) async {
          recorded.callCount++;
          recorded.providerAndroid = providerAndroid;
        },
      );

      await service.initialize();

      expect(recorded.providerAndroid, isA<AndroidDebugProvider>());
    });

    test(
        'production never activates the debug provider — Play Integrity instead',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final recorded = _RecordingActivation();
      final service = FirebaseAppCheckService(
        allowsDebugTooling: false,
        loggingService: _RecordingLoggingService(),
        activate: (
            {providerAndroid,
            providerApple,
            providerWeb,
            providerWindows}) async {
          recorded.callCount++;
          recorded.providerAndroid = providerAndroid;
        },
      );

      await service.initialize();

      expect(recorded.providerAndroid, isA<AndroidPlayIntegrityProvider>());
      expect(recorded.providerAndroid, isNot(isA<AndroidDebugProvider>()));
    });
  });

  group('FirebaseAppCheckService — iOS/macOS', () {
    test('development activates the debug provider', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final recorded = _RecordingActivation();
      final service = FirebaseAppCheckService(
        allowsDebugTooling: true,
        loggingService: _RecordingLoggingService(),
        activate: (
            {providerAndroid,
            providerApple,
            providerWeb,
            providerWindows}) async {
          recorded.providerApple = providerApple;
        },
      );

      await service.initialize();

      expect(recorded.providerApple, isA<AppleDebugProvider>());
    });

    test(
        'production activates App Attest with DeviceCheck fallback, never debug',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final recorded = _RecordingActivation();
      final service = FirebaseAppCheckService(
        allowsDebugTooling: false,
        loggingService: _RecordingLoggingService(),
        activate: (
            {providerAndroid,
            providerApple,
            providerWeb,
            providerWindows}) async {
          recorded.providerApple = providerApple;
        },
      );

      await service.initialize();

      expect(
        recorded.providerApple,
        isA<AppleAppAttestWithDeviceCheckFallbackProvider>(),
      );
      expect(recorded.providerApple, isNot(isA<AppleDebugProvider>()));
    });
  });

  group('FirebaseAppCheckService — Windows', () {
    test('development activates the (only available) debug provider', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final recorded = _RecordingActivation();
      final service = FirebaseAppCheckService(
        allowsDebugTooling: true,
        loggingService: _RecordingLoggingService(),
        activate: (
            {providerAndroid,
            providerApple,
            providerWeb,
            providerWindows}) async {
          recorded.callCount++;
          recorded.providerWindows = providerWindows;
        },
      );

      await service.initialize();

      expect(recorded.providerWindows, isA<WindowsDebugProvider>());
    });

    test(
        'production does not activate App Check at all (no non-debug provider exists)',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final recorded = _RecordingActivation();
      final logger = _RecordingLoggingService();
      final service = FirebaseAppCheckService(
        allowsDebugTooling: false,
        loggingService: logger,
        activate: (
            {providerAndroid,
            providerApple,
            providerWeb,
            providerWindows}) async {
          recorded.callCount++;
        },
      );

      await service.initialize();

      expect(recorded.callCount, 0);
      expect(logger.levels, contains(LogLevel.info));
    });
  });

  // FirebaseAppCheckService's Web branch is gated by kIsWeb, a compile-time
  // constant that's `false` for this suite's default VM test run — it
  // can't be exercised or asserted against from here (running under
  // `flutter test --platform chrome` would compile a different constant
  // and a different set of testable branches entirely). Its "no site key
  // configured → log and skip, never throw" behavior is the same shape
  // already covered by the Windows/Linux no-op tests below.

  group('FirebaseAppCheckService — Linux/Fuchsia', () {
    test('is an intentional no-op, never throws', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final recorded = _RecordingActivation();
      final logger = _RecordingLoggingService();
      final service = FirebaseAppCheckService(
        allowsDebugTooling: true,
        loggingService: logger,
        activate: (
            {providerAndroid,
            providerApple,
            providerWeb,
            providerWindows}) async {
          recorded.callCount++;
        },
      );

      await expectLater(service.initialize(), completes);
      expect(recorded.callCount, 0);
      expect(logger.levels, contains(LogLevel.info));
    });
  });

  group('FirebaseAppCheckService — failure handling', () {
    test('never throws when the underlying activation fails', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final logger = _RecordingLoggingService();
      final service = FirebaseAppCheckService(
        allowsDebugTooling: false,
        loggingService: logger,
        activate: (
            {providerAndroid,
            providerApple,
            providerWeb,
            providerWindows}) async {
          throw Exception('activation failed');
        },
      );

      await expectLater(service.initialize(), completes);
      expect(logger.levels, [LogLevel.error]);
    });
  });
}
