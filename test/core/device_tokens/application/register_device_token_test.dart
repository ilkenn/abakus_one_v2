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
        token: 'fcm-token-abc',
        platform: 'android',
        now: DateTime(2026, 8, 5),
      );

      expect(token.uid, 'uid-1');
      expect(token.token, 'fcm-token-abc');
      expect(token.isActive, isTrue);
      expect(await repository.findByToken('fcm-token-abc'), token);
    });

    test('re-registering the same active token returns the existing record',
        () async {
      final repository = InMemoryDeviceTokenRepository();
      final useCase = RegisterDeviceToken(
        repository: repository,
        idGenerator: SequentialDeviceTokenIdGenerator(),
      );

      final first = await useCase.call(
        uid: 'uid-1',
        token: 'fcm-token-abc',
        platform: 'android',
        now: DateTime(2026, 8, 5),
      );
      final second = await useCase.call(
        uid: 'uid-1',
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
        token: 'fcm-token-abc',
        platform: 'android',
        now: DateTime(2026, 8, 5),
      );
      await repository.save(first.copyWith(revokedAt: DateTime(2026, 8, 6)));

      final second = await useCase.call(
        uid: 'uid-1',
        token: 'fcm-token-abc',
        platform: 'android',
        now: DateTime(2026, 8, 7),
      );

      expect(second.id, isNot(first.id));
      expect(second.isActive, isTrue);
    });
  });
}
