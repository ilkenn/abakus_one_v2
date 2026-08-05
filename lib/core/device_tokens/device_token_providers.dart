import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'application/device_token_id_generator.dart';
import 'application/register_device_token.dart';
import 'application/revoke_device_token.dart';
import 'data/device_token_repository.dart';

/// Central Riverpod wiring for `core/device_tokens` — Sprint 9H
/// (`docs/decisions.md` ADR-026). Mirrors `core/account_deletion`'s own
/// provider-file shape.
final deviceTokenRepositoryProvider = Provider<DeviceTokenRepository>((ref) {
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
