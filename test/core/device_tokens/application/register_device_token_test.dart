import 'package:abakus_one_v2/core/device_tokens/application/device_token_id_generator.dart';
import 'package:abakus_one_v2/core/device_tokens/application/register_device_token.dart';
import 'package:abakus_one_v2/core/device_tokens/data/device_token_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RegisterDeviceToken', () {
    test('creates a new active token for the given uid', () async {
      final repository = InMemoryDeviceTokenRepository();
      final useCase = RegisterDeviceToken(
        repository: repository,
        idGenerator: SequentialDeviceTokenIdGenerator(),
      );

      final token = await useCase.call(
        uid: 'uid-1',
        organizationId: 'org-1',
        token: 'fcm-token-abc',
        platform: 'android',
        now: DateTime(2026, 8, 5),
      );

      expect(token.uid, 'uid-1');
      expect(token.organizationId, 'org-1');
      expect(token.token, 'fcm-token-abc');
      expect(token.isActive, isTrue);
      expect(await repository.findByToken('fcm-token-abc'), token);
    });

    test(
        're-registering the same active token for the same uid returns the existing record',
        () async {
      final repository = InMemoryDeviceTokenRepository();
      final useCase = RegisterDeviceToken(
        repository: repository,
        idGenerator: SequentialDeviceTokenIdGenerator(),
      );

      final first = await useCase.call(
        uid: 'uid-1',
        organizationId: 'org-1',
        token: 'fcm-token-abc',
        platform: 'android',
        now: DateTime(2026, 8, 5),
      );
      final second = await useCase.call(
        uid: 'uid-1',
        organizationId: 'org-1',
        token: 'fcm-token-abc',
        platform: 'android',
        now: DateTime(2026, 8, 6),
      );

      expect(second.id, first.id);
      expect(second.registeredAt, first.registeredAt);
    });

    test('re-registering a revoked token creates a fresh active record',
        () async {
      final repository = InMemoryDeviceTokenRepository();
      final useCase = RegisterDeviceToken(
        repository: repository,
        idGenerator: SequentialDeviceTokenIdGenerator(),
      );
      final first = await useCase.call(
        uid: 'uid-1',
        organizationId: 'org-1',
        token: 'fcm-token-abc',
        platform: 'android',
        now: DateTime(2026, 8, 5),
      );
      await repository.save(first.copyWith(revokedAt: DateTime(2026, 8, 6)));

      final second = await useCase.call(
        uid: 'uid-1',
        organizationId: 'org-1',
        token: 'fcm-token-abc',
        platform: 'android',
        now: DateTime(2026, 8, 7),
      );

      expect(second.id, isNot(first.id));
      expect(second.isActive, isTrue);
    });

    // Faz R.3C — regression test for the cross-customer-reassociation bug:
    // the same physical device token re-registering under a *different*
    // uid (a shared/reused device, customer A signs out, customer B signs
    // in and registers) must never stay "active" under customer A.
    test(
        'the same physical token re-registering under a different uid revokes the old owner and creates a fresh record for the new uid',
        () async {
      final repository = InMemoryDeviceTokenRepository();
      final useCase = RegisterDeviceToken(
        repository: repository,
        idGenerator: SequentialDeviceTokenIdGenerator(),
      );

      final customerA = await useCase.call(
        uid: 'customer-a',
        organizationId: 'org-1',
        token: 'shared-device-token',
        platform: 'android',
        now: DateTime(2026, 8, 5),
      );

      final customerB = await useCase.call(
        uid: 'customer-b',
        organizationId: 'org-1',
        token: 'shared-device-token',
        platform: 'android',
        now: DateTime(2026, 8, 6),
      );

      expect(customerB.uid, 'customer-b');
      expect(customerB.id, isNot(customerA.id));
      expect(customerB.isActive, isTrue);

      final activeForA = await repository.findActiveByUid('customer-a');
      expect(activeForA, isEmpty);
      final activeForB = await repository.findActiveByUid('customer-b');
      expect(activeForB, [customerB]);
    });
  });
}
