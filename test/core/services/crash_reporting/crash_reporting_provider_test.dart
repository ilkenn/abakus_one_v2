import 'package:abakus_one_v2/bootstrap/firebase_ready_provider.dart';
import 'package:abakus_one_v2/core/services/crash_reporting/crash_reporting_provider.dart';
import 'package:abakus_one_v2/core/services/crash_reporting/firebase_crashlytics_service.dart';
import 'package:abakus_one_v2/core/services/crash_reporting/noop_crash_reporting_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('crashReportingServiceProvider', () {
    test(
        'resolves to NoOpCrashReportingService when Firebase is not ready '
        '(default)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(crashReportingServiceProvider),
        isA<NoOpCrashReportingService>(),
      );
    });

    test('resolves to FirebaseCrashlyticsService when Firebase is ready', () {
      final container = ProviderContainer(
        overrides: [firebaseReadyProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);

      expect(
        container.read(crashReportingServiceProvider),
        isA<FirebaseCrashlyticsService>(),
      );
    });
  });
}
