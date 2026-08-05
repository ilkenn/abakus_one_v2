import 'package:abakus_one_v2/features/admin/data/staff_auth_repository.dart';
import 'package:abakus_one_v2/features/admin/data/staff_member_repository.dart';
import 'package:abakus_one_v2/features/admin/domain/staff/staff_member_status.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/staff_role.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/services/auth/fake_email_password_auth_client.dart';
import '../test_support/admin_test_fixtures.dart';

void main() {
  group('FirebaseStaffAuthRepository', () {
    test(
        'signIn succeeds only when the credential is valid AND the '
        'resulting uid is linked to an active StaffMember with roles',
        () async {
      final authClient = FakeEmailPasswordAuthClient();
      final created = await authClient.createAccount(
          email: 'manager@abakus.test', password: 'S3curePass!');
      final memberRepository = InMemoryStaffMemberRepository();
      await memberRepository.save(buildTestStaffMember(
        id: 'staff-1',
        roles: {StaffRole.manager},
        authUid: created.uid,
      ));
      final repository = FirebaseStaffAuthRepository(
        authClient: authClient,
        staffMemberRepository: memberRepository,
        sessionDuration: () => const Duration(hours: 1),
      );

      final session = await repository.signIn(
          email: 'manager@abakus.test', password: 'S3curePass!');

      expect(session, isNotNull);
      expect(session!.actorId, 'staff-1');
      expect(session.roles, {StaffRole.manager});
    });

    test('signIn denies a valid credential with no linked StaffMember',
        () async {
      final authClient = FakeEmailPasswordAuthClient();
      await authClient.createAccount(
          email: 'nobody@abakus.test', password: 'S3curePass!');
      final repository = FirebaseStaffAuthRepository(
        authClient: authClient,
        staffMemberRepository: InMemoryStaffMemberRepository(),
        sessionDuration: () => const Duration(hours: 1),
      );

      final session = await repository.signIn(
          email: 'nobody@abakus.test', password: 'S3curePass!');

      expect(session, isNull);
    });

    test('signIn denies an invalid credential outright', () async {
      final authClient = FakeEmailPasswordAuthClient();
      final repository = FirebaseStaffAuthRepository(
        authClient: authClient,
        staffMemberRepository: InMemoryStaffMemberRepository(),
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
      final memberRepository = InMemoryStaffMemberRepository();
      await memberRepository.save(buildTestStaffMember(
        id: 'staff-1',
        roles: {StaffRole.staff},
        status: StaffMemberStatus.suspended,
        authUid: created.uid,
      ));
      final repository = FirebaseStaffAuthRepository(
        authClient: authClient,
        staffMemberRepository: memberRepository,
        sessionDuration: () => const Duration(hours: 1),
      );

      final session = await repository.signIn(
          email: 'suspended@abakus.test', password: 'S3curePass!');

      expect(session, isNull);
    });
  });
}
