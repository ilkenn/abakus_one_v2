import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/core/services/logging/console_logging_service.dart';
import 'package:abakus_one_v2/core/services/logging/logging_provider.dart';

void main() {
  group('loggingServiceProvider', () {
    test('resolves to ConsoleLoggingService outside a release build', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final service = container.read(loggingServiceProvider);

      // flutter_test always runs in debug mode, so kReleaseMode is false —
      // this exercises the non-release branch. The release branch
      // (NoOpLoggingService) is a single-line compile-time constant and
      // isn't independently reachable from a widget/unit test.
      expect(service, isA<ConsoleLoggingService>());
    });

    test('resolution is deterministic across reads', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final first = container.read(loggingServiceProvider);
      final second = container.read(loggingServiceProvider);

      expect(first.runtimeType, second.runtimeType);
    });
  });
}
