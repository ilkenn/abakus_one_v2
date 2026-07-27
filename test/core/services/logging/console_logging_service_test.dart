import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/core/services/logging/console_logging_service.dart';
import 'package:abakus_one_v2/core/services/logging/log_level.dart';

void main() {
  group('ConsoleLoggingService', () {
    const service = ConsoleLoggingService();
    late DebugPrintCallback originalDebugPrint;
    late List<String?> printed;

    setUp(() {
      originalDebugPrint = debugPrint;
      printed = [];
      debugPrint = (String? message, {int? wrapWidth}) {
        printed.add(message);
      };
    });

    tearDown(() {
      debugPrint = originalDebugPrint;
    });

    group('severity handling', () {
      for (final level in LogLevel.values) {
        test('$level logs without throwing and includes the level name', () {
          expect(
            () => service.log(level, 'a message'),
            returnsNormally,
          );
          expect(printed, hasLength(1));
          expect(printed.single, contains(level.name.toUpperCase()));
        });
      }
    });

    test('includes the message text', () {
      service.log(LogLevel.info, 'user tapped checkout');
      expect(printed.single, contains('user tapped checkout'));
    });

    test('includes the error and stack trace when provided', () {
      final stackTrace = StackTrace.current;
      service.log(
        LogLevel.error,
        'checkout failed',
        error: Exception('boom'),
        stackTrace: stackTrace,
      );

      expect(printed.single, contains('boom'));
      expect(printed.single, contains(stackTrace.toString()));
    });

    test('redacts sensitive context entries before printing', () {
      service.log(
        LogLevel.debug,
        'otp requested',
        context: {'phone': '+905321234567', 'screen': 'LoginScreen'},
      );

      expect(printed.single, isNot(contains('+905321234567')));
      expect(printed.single, contains('[REDACTED]'));
      expect(printed.single, contains('LoginScreen'));
    });

    test('omits the context segment entirely when context is empty', () {
      service.log(LogLevel.debug, 'no context', context: const {});
      expect(printed.single, isNot(contains('context:')));
    });

    test('redacts sensitive data embedded directly in the message text', () {
      service.log(
        LogLevel.warning,
        'login failed for user with token=abc123xyz and '
        'phone +905321234567',
      );

      expect(printed.single, isNot(contains('abc123xyz')));
      expect(printed.single, isNot(contains('905321234567')));
      expect(printed.single, contains('[REDACTED]'));
    });

    test('redacts sensitive data embedded in the error text', () {
      service.log(
        LogLevel.error,
        'checkout failed',
        error: Exception('payment declined for card 4111 1111 1111 1111, '
            'contact test@example.com'),
      );

      expect(printed.single, isNot(contains('4111 1111 1111 1111')));
      expect(printed.single, isNot(contains('test@example.com')));
      expect(printed.single, contains('[REDACTED]'));
    });

    test(
        'never throws even if the underlying debugPrint implementation '
        'throws', () {
      debugPrint = (String? message, {int? wrapWidth}) {
        throw StateError('console unavailable');
      };

      expect(
        () => service.log(LogLevel.error, 'still safe'),
        returnsNormally,
      );
    });
  });
}
