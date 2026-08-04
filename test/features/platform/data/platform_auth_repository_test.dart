import 'package:abakus_one_v2/features/platform/data/platform_auth_repository.dart';
import 'package:abakus_one_v2/features/platform/data/platform_member_repository.dart';
import 'package:abakus_one_v2/features/platform/domain/authorization/platform_role.dart';
import 'package:abakus_one_v2/features/platform/domain/member/platform_member.dart';
import 'package:abakus_one_v2/features/platform/domain/member/platform_member_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DevelopmentPlatformAuthRepository', () {
    test('signIn issues a session for an active member with roles', () async {
      final memberRepository = InMemoryPlatformMemberRepository();
      await memberRepository.save(PlatformMember(
        id: 'platform-1',
        displayName: 'Test',
        roles: const {PlatformRole.platformOwner},
        createdAt: DateTime(2026, 1, 1),
        revision: 1,
      ));
      final repository = DevelopmentPlatformAuthRepository(
        platformMemberRepository: memberRepository,
        sessionDuration: () => const Duration(hours: 1),
      );

      final session = await repository.signIn(platformMemberId: 'platform-1');

      expect(session, isNotNull);
      expect(session!.actorId, 'platform-1');
      expect(session.roles, {PlatformRole.platformOwner});
      expect(session.isValid, isTrue);
    });

    test('signIn denies an unknown platform member', () async {
      final repository = DevelopmentPlatformAuthRepository(
        platformMemberRepository: InMemoryPlatformMemberRepository(),
        sessionDuration: () => const Duration(hours: 1),
      );

      final session = await repository.signIn(platformMemberId: 'missing');

      expect(session, isNull);
    });

    test('signIn denies a suspended member', () async {
      final memberRepository = InMemoryPlatformMemberRepository();
      await memberRepository.save(PlatformMember(
        id: 'platform-1',
        displayName: 'Test',
        roles: const {PlatformRole.platformAdministrator},
        status: PlatformMemberStatus.suspended,
        createdAt: DateTime(2026, 1, 1),
        revision: 1,
      ));
      final repository = DevelopmentPlatformAuthRepository(
        platformMemberRepository: memberRepository,
        sessionDuration: () => const Duration(hours: 1),
      );

      final session = await repository.signIn(platformMemberId: 'platform-1');

      expect(session, isNull);
    });

    test(
        'refreshSession denies a session issued before a forced '
        'revocation', () async {
      final memberRepository = InMemoryPlatformMemberRepository();
      await memberRepository.save(PlatformMember(
        id: 'platform-1',
        displayName: 'Test',
        roles: const {PlatformRole.platformOwner},
        createdAt: DateTime(2026, 1, 1),
        revision: 1,
      ));
      final repository = DevelopmentPlatformAuthRepository(
        platformMemberRepository: memberRepository,
        sessionDuration: () => const Duration(hours: 1),
      );
      final original = await repository.signIn(platformMemberId: 'platform-1');
      await Future<void>.delayed(const Duration(milliseconds: 5));

      final member = await memberRepository.findById('platform-1');
      await memberRepository.save(member!.copyWith(
        sessionsRevokedAt: DateTime.now(),
        revision: member.revision + 1,
      ));

      final refreshed = await repository.refreshSession(original!);

      expect(refreshed, isNull);
    });

    test('refreshSession denies once the member becomes suspended', () async {
      final memberRepository = InMemoryPlatformMemberRepository();
      await memberRepository.save(PlatformMember(
        id: 'platform-1',
        displayName: 'Test',
        roles: const {PlatformRole.platformAdministrator},
        createdAt: DateTime(2026, 1, 1),
        revision: 1,
      ));
      final repository = DevelopmentPlatformAuthRepository(
        platformMemberRepository: memberRepository,
        sessionDuration: () => const Duration(hours: 1),
      );
      final original = await repository.signIn(platformMemberId: 'platform-1');

      final member = await memberRepository.findById('platform-1');
      await memberRepository.save(member!.copyWith(
        status: PlatformMemberStatus.suspended,
        revision: member.revision + 1,
      ));

      final refreshed = await repository.refreshSession(original!);

      expect(refreshed, isNull);
    });
  });

  group('ProductionUnavailablePlatformAuthRepository', () {
    test(
        'signIn always denies — "release builds must never expose this '
        'path"', () async {
      const repository = ProductionUnavailablePlatformAuthRepository();

      final session = await repository.signIn(platformMemberId: 'platform-1');

      expect(session, isNull);
    });
  });
}
