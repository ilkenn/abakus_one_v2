import 'package:abakus_one_v2/core/device_tokens/application/device_token_id_generator.dart';
import 'package:abakus_one_v2/core/device_tokens/application/register_device_token.dart';
import 'package:abakus_one_v2/core/device_tokens/application/revoke_device_token.dart';
import 'package:abakus_one_v2/core/device_tokens/data/device_token_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RevokeDeviceTokensForUser', () {
    test('revokes every active token for the uid, leaving others untouched',
        () async {
      final repository = InMemoryDeviceTokenRepository();
      final register = RegisterDeviceToken(
        repository: repository,
        idGenerator: SequentialDeviceTokenIdGenerator(),
      );
      await register.call(
        uid: 'uid-1',
        organizationId: 'org-1',
        token: 'token-a',
        platform: 'android',
        now: DateTime(2026, 8, 1),
      );
      await register.call(
        uid: 'uid-1',
        organizationId: 'org-1',
        token: 'token-b',
        platform: 'ios',
        now: DateTime(2026, 8, 1),
      );
      await register.call(
        uid: 'uid-2',
        organizationId: 'org-1',
        token: 'token-c',
        platform: 'android',
        now: DateTime(2026, 8, 1),
      );

      await RevokeDeviceTokensForUser(repository: repository)
          .call(uid: 'uid-1', now: DateTime(2026, 8, 5));

      expect(await repository.findActiveByUid('uid-1'), isEmpty);
      expect(await repository.findActiveByUid('uid-2'), hasLength(1));
    });

    test('is idempotent — revoking with no active tokens is a safe no-op',
        () async {
      final repository = InMemoryDeviceTokenRepository();

      await RevokeDeviceTokensForUser(repository: repository)
          .call(uid: 'uid-1', now: DateTime(2026, 8, 5));

      expect(await repository.findActiveByUid('uid-1'), isEmpty);
    });
  });
}
