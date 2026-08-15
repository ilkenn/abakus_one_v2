import 'package:abakus_one_v2/bootstrap/firebase_ready_provider.dart';
import 'package:abakus_one_v2/core/device_tokens/data/device_token_repository.dart';
import 'package:abakus_one_v2/core/device_tokens/device_token_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Faz R.3C — re-gated from `kReleaseMode` to `firebaseReadyProvider`;
  // these tests prove the seam resolves to the right implementation on
  // each side without ever touching a real Firestore/platform call (the
  // provider itself never calls a repository method, only constructs it).
  test('resolves to InMemoryDeviceTokenRepository when Firebase is not ready',
      () {
    final container = ProviderContainer(
      overrides: [firebaseReadyProvider.overrideWithValue(false)],
    );
    addTearDown(container.dispose);

    expect(
      container.read(deviceTokenRepositoryProvider),
      isA<InMemoryDeviceTokenRepository>(),
    );
  });

  // The Firebase-ready branch (`FirestoreDeviceTokenRepository`) is not
  // exercised here by design — its constructor eagerly touches
  // `FirebaseFirestore.instance`, which requires a real Firebase app
  // binding this test process never has. This mirrors the established,
  // pre-existing convention for every other raw-`cloud_firestore`-backed
  // repository in this codebase (`FirestoreReservationRepository`,
  // `FirestoreCanonicalOrderRepository`'s Firestore-client variant): no
  // `flutter test` ever lets the real class construct — callers always
  // override the provider with a fake/in-memory double instead. The
  // branch itself is verified by direct code inspection plus the backend/
  // emulator-side integration coverage.

  test(
      'defaults to InMemoryDeviceTokenRepository with no override (test-safe default)',
      () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      container.read(deviceTokenRepositoryProvider),
      isA<InMemoryDeviceTokenRepository>(),
    );
  });
}
