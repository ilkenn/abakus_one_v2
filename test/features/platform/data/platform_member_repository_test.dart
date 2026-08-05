import 'package:abakus_one_v2/features/platform/data/platform_member_repository.dart';
import 'package:abakus_one_v2/features/platform/domain/authorization/platform_role.dart';
import 'package:abakus_one_v2/features/platform/domain/member/platform_member.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InMemoryPlatformMemberRepository (development/debug behavior)', () {
    test('a saved member is enumerable via findAll and findById', () async {
      final repository = InMemoryPlatformMemberRepository();
      final member = PlatformMember(
        id: 'platform-1',
        displayName: 'Olivia Owner',
        roles: const {PlatformRole.platformOwner},
        createdAt: DateTime(2026, 1, 1),
        revision: 1,
      );

      await repository.save(member);

      expect((await repository.findAll()).single.displayName, 'Olivia Owner');
      expect((await repository.findById('platform-1'))?.displayName,
          'Olivia Owner');
    });
  });

  group(
      'ProductionUnavailablePlatformMemberRepository (Phase 8 closure '
      'sprint — release builds)', () {
    const repository = ProductionUnavailablePlatformMemberRepository();

    test('findAll exposes zero member metadata — no accounts', () async {
      expect(await repository.findAll(), isEmpty);
    });

    test(
        'findById never resolves any member — no names, roles, or '
        'statuses leak', () async {
      expect(await repository.findById('platform-1'), isNull);
    });

    test(
        'save is unavailable — the roster can never be populated in a '
        'release build either', () async {
      final member = PlatformMember(
        id: 'platform-1',
        displayName: 'Olivia Owner',
        roles: const {PlatformRole.platformOwner},
        createdAt: DateTime(2026, 1, 1),
        revision: 1,
      );

      expect(() => repository.save(member), throwsA(isA<StateError>()));
    });
  });
}
