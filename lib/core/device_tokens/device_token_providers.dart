import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'application/device_token_id_generator.dart';
import 'application/register_device_token.dart';
import 'application/revoke_device_token.dart';
import 'data/device_token_repository.dart';

/// Central Riverpod wiring for `core/device_tokens` — Sprint 9H
/// (`docs/decisions.md` ADR-026). Mirrors `core/account_deletion`'s own
/// provider-file shape.
///
/// `kReleaseMode`-gated — closed during this phase's mandatory
/// adversarial security review alongside the identical
/// `accountDeletionRequestRepositoryProvider` fix: no Firestore-backed
/// implementation exists yet, so this previously resolved to
/// `InMemory*` unconditionally, including in release builds. The honest
/// consequence: push-notification device-token registration is
/// non-functional in release builds until a real Firestore-backed
/// repository exists — a real, named gap, not a security hole (a failed
/// registration only means that device misses push notifications).
final deviceTokenRepositoryProvider = Provider<DeviceTokenRepository>((ref) {
  if (kReleaseMode) {
    return const ProductionUnavailableDeviceTokenRepository();
  }
  return InMemoryDeviceTokenRepository();
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
