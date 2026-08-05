import 'package:abakus_one_v2/features/platform/data/platform_auth_repository.dart';
import 'package:abakus_one_v2/features/platform/data/platform_member_repository.dart';
import 'package:abakus_one_v2/features/platform/domain/authorization/platform_role.dart';
import 'package:abakus_one_v2/features/platform/domain/member/platform_member.dart';
import 'package:abakus_one_v2/features/platform/domain/member/platform_member_status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/services/auth/fake_email_password_auth_client.dart';

void main() {
  group('FirebasePlatformAuthRepository', () {
    test(
        'signIn succeeds only when the credential is valid AND the '
        'resulting uid is linked to an active PlatformMember with roles',
        () async {
      final authClient = FakeEmailPasswordAuthClient();
      final created = await authClient.createAccount(
          email: 'owner@abakus.test', password: 'S3curePass!');
      final memberRepository = InMemoryPlatformMemberRepository();
      await memberRepository.save(PlatformMember(
        id: 'platform-1',
        displayName: 'Test',
        roles: const {PlatformRole.platformOwner},
        authUid: created.uid,
        createdAt: DateTime(2026, 1, 1),
        revision: 1,
      ));
      final repository = FirebasePlatformAuthRepository(
        authClient: authClient,
        platformMemberRepository: memberRepository,
        sessionDuration: () => const Duration(hours: 1),
      );

      final session = await repository.signIn(
          email: 'owner@abakus.test', password: 'S3curePass!');

      expect(session, isNotNull);
      expect(session!.actorId, 'platform-1');
      expect(session.roles, {PlatformRole.platformOwner});
    });

    test('signIn denies a valid credential with no linked PlatformMember',
        () async {
      final authClient = FakeEmailPasswordAuthClient();
      await authClient.createAccount(
          email: 'nobody@abakus.test', password: 'S3curePass!');
      final repository = FirebasePlatformAuthRepository(
        authClient: authClient,
        platformMemberRepository: InMemoryPlatformMemberRepository(),
        sessionDuration: () => const Duration(hours: 1),
      );

      final session = await repository.signIn(
          email: 'nobody@abakus.test', password: 'S3curePass!');

      expect(session, isNull);
    });

    test('signIn denies an invalid credential outright', () async {
      final authClient = FakeEmailPasswordAuthClient();
      final repository = FirebasePlatformAuthRepository(
        authClient: authClient,
        platformMemberRepository: InMemoryPlatformMemberRepository(),
        sessionDuration: () => const Duration(hours: 1),
      );

      final session = await repository.signIn(
          email: 'nobody@abakus.test', password: 'wrong');

      expect(session, isNull);
    });

    test('signIn denies a valid credential linked to a suspended member',
        () async {
      final authClient = FakeEmailPasswordAuthClient();
      final created = await authClient.createAccount(
          email: 'suspended@abakus.test', password: 'S3curePass!');
      final memberRepository = InMemoryPlatformMemberRepository();
      await memberRepository.save(PlatformMember(
        id: 'platform-1',
        displayName: 'Test',
        roles: const {PlatformRole.platformAdministrator},
        status: PlatformMemberStatus.suspended,
        authUid: created.uid,
        createdAt: DateTime(2026, 1, 1),
        revision: 1,
      ));
      final repository = FirebasePlatformAuthRepository(
        authClient: authClient,
        platformMemberRepository: memberRepository,
        sessionDuration: () => const Duration(hours: 1),
      );

      final session = await repository.signIn(
          email: 'suspended@abakus.test', password: 'S3curePass!');

      expect(session, isNull);
    });
  });
}
