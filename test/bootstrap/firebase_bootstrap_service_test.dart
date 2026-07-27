import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/bootstrap/firebase_bootstrap_service.dart';
import 'package:abakus_one_v2/core/services/logging/log_level.dart';
import 'package:abakus_one_v2/core/services/logging/logging_service.dart';

class _RecordingLoggingService implements LoggingService {
  final List<LogLevel> levels = [];
  final List<String> messages = [];
  final List<Object?> errors = [];

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
    errors.add(error);
  }
}

void main() {
  group('FirebaseBootstrapService.initialize — success', () {
    test('returns true and logs nothing when initialization succeeds',
        () async {
      final logger = _RecordingLoggingService();
      final service = FirebaseBootstrapService(
        loggingService: logger,
        initializeApp: ({options}) async {},
      );

      final result = await service.initialize();

      expect(result, isTrue);
      expect(logger.messages, isEmpty);
    });
  });

  group('FirebaseBootstrapService.initialize — failure', () {
    test('returns false, never throws, when initialization fails', () async {
      final logger = _RecordingLoggingService();
      final service = FirebaseBootstrapService(
        loggingService: logger,
        initializeApp: ({options}) async {
          throw Exception('network unavailable');
        },
      );

      final result = await service.initialize();

      expect(result, isFalse);
    });

    test('logs the failure at error severity, mapped through ErrorMapper',
        () async {
      final logger = _RecordingLoggingService();
      final service = FirebaseBootstrapService(
        loggingService: logger,
        initializeApp: ({options}) async {
          throw Exception('network unavailable');
        },
      );

      await service.initialize();

      expect(logger.levels, [LogLevel.error]);
      expect(logger.errors.single, isA<Exception>());
    });

    test(
        'never logs the raw exception message as the log message itself '
        '— only ErrorMapper\'s generic, user-safe Failure.message', () async {
      final logger = _RecordingLoggingService();
      const secretLookingMessage =
          'apiKey=AIzaSySECRETLOOKINGVALUE rejected by server';
      final service = FirebaseBootstrapService(
        loggingService: logger,
        initializeApp: ({options}) async {
          throw Exception(secretLookingMessage);
        },
      );

      await service.initialize();

      expect(logger.messages.single, isNot(contains('AIzaSy')));
    });

    test('propagates no exception out of initialize() itself', () async {
      final logger = _RecordingLoggingService();
      final service = FirebaseBootstrapService(
        loggingService: logger,
        initializeApp: ({options}) async {
          throw StateError('unexpected SDK state');
        },
      );

      await expectLater(service.initialize(), completes);
    });
  });
}
