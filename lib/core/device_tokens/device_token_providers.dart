import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../bootstrap/firebase_ready_provider.dart';
import 'application/device_token_id_generator.dart';
import 'application/register_device_token.dart';
import 'application/revoke_device_token.dart';
import 'data/device_token_repository.dart';

/// Central Riverpod wiring for `core/device_tokens` — Sprint 9H
/// (`docs/decisions.md` ADR-026), superseded by Faz R.3C.
///
/// **Faz R.3C**: re-gated from `kReleaseMode` to [firebaseReadyProvider],
/// mirroring [canonicalOrderRepositoryProvider]'s own real/in-memory split
/// — a disclosed, intentional supersession of the prior "no release build
/// may silently persist in memory only" gate, now that
/// [FirestoreDeviceTokenRepository] genuinely exists: once Firebase is
/// ready (in any build mode, including `flutter test`'s default "not
/// ready"), registration is real and durable; otherwise it falls back to
/// [InMemoryDeviceTokenRepository] rather than failing closed, since a
/// missed device-token registration before Firebase finishes bootstrapping
/// only means that device misses push notifications, not a security gap.
final deviceTokenRepositoryProvider = Provider<DeviceTokenRepository>((ref) {
  final isFirebaseReady = ref.watch(firebaseReadyProvider);
  if (!isFirebaseReady) {
    return InMemoryDeviceTokenRepository();
  }
  return FirestoreDeviceTokenRepository();
});

final deviceTokenIdGeneratorProvider = Provider<DeviceTokenIdGenerator>((ref) {
  return SequentialDeviceTokenIdGenerator();
});

final registerDeviceTokenProvider = Provider<RegisterDeviceToken>((ref) {
  return RegisterDeviceToken(
    repository: ref.watch(deviceTokenRepositoryProvider),
    idGenerator: ref.watch(deviceTokenIdGeneratorProvider),
  );
});

final revokeDeviceTokensForUserProvider =
    Provider<RevokeDeviceTokensForUser>((ref) {
  return RevokeDeviceTokensForUser(
    repository: ref.watch(deviceTokenRepositoryProvider),
  );
});
