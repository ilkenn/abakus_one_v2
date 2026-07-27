import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/core/services/logging/log_level.dart';
import 'package:abakus_one_v2/core/services/logging/noop_logging_service.dart';

void main() {
  group('NoOpLoggingService', () {
    const service = NoOpLoggingService();

    test('logging at every severity never throws', () {
      for (final level in LogLevel.values) {
        expect(() => service.log(level, 'anything'), returnsNormally);
      }
    });

    test('logging with error, stack trace, and context never throws', () {
      expect(
        () => service.log(
          LogLevel.error,
          'anything',
          error: Exception('boom'),
          stackTrace: StackTrace.current,
          context: {'token': 'abc123'},
        ),
        returnsNormally,
      );
    });
  });
}
