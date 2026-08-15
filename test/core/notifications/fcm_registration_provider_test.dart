import 'package:abakus_one_v2/bootstrap/firebase_ready_provider.dart';
import 'package:abakus_one_v2/core/notifications/fcm_registration_provider.dart';
import 'package:abakus_one_v2/core/notifications/fcm_registration_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Faz R.3C — `fcmRegistrationServiceProvider` must never construct the
  // real `firebase_messaging`-backed service unless Firebase is ready,
  // matching every other real-Firebase-service provider in this codebase.
  // This is also what makes it safe by construction for `flutter test`:
  // `firebaseReadyProvider` defaults to `false`, so no test run ever
  // touches a real platform channel through this seam.
  test('resolves to NoOpFcmRegistrationService when Firebase is not ready', () {
    final container = ProviderContainer(
      overrides: [firebaseReadyProvider.overrideWithValue(false)],
    );
    addTearDown(container.dispose);

    expect(
      container.read(fcmRegistrationServiceProvider),
      isA<NoOpFcmRegistrationService>(),
    );
  });

  test(
      'defaults to NoOpFcmRegistrationService with no override (test-safe default)',
      () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      container.read(fcmRegistrationServiceProvider),
      isA<NoOpFcmRegistrationService>(),
    );
  });

  test('NoOpFcmRegistrationService.registerForUid completes without throwing',
      () async {
    const service = NoOpFcmRegistrationService();

    await expectLater(
      service.registerForUid(uid: 'uid-1'),
      completes,
    );
  });
}
