import 'package:abakus_one_v2/features/admin/data/staff_auth_repository.dart';
import 'package:abakus_one_v2/features/admin/data/staff_member_repository.dart';
import 'package:abakus_one_v2/features/admin/domain/staff/staff_member_status.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/staff_role.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/admin_test_fixtures.dart';

void main() {
  group('DevelopmentStaffAuthRepository', () {
    test('signIn issues a session for an active member with roles', () async {
      final memberRepository = InMemoryStaffMemberRepository();
      await memberRepository.save(
          buildTestStaffMember(id: 'staff-1', roles: {StaffRole.manager}));
      final repository = DevelopmentStaffAuthRepository(
        staffMemberRepository: memberRepository,
        sessionDuration: () => const Duration(hours: 1),
      );

      final session = await repository.signIn(staffMemberId: 'staff-1');

      expect(session, isNotNull);
      expect(session!.actorId, 'staff-1');
      expect(session.roles, {StaffRole.manager});
      expect(session.isValid, isTrue);
    });

    test('signIn denies an unknown staff member', () async {
      final repository = DevelopmentStaffAuthRepository(
        staffMemberRepository: InMemoryStaffMemberRepository(),
        sessionDuration: () => const Duration(hours: 1),
      );

      final session = await repository.signIn(staffMemberId: 'missing');

      expect(session, isNull);
    });

    test('signIn denies a suspended member', () async {
      final memberRepository = InMemoryStaffMemberRepository();
      await memberRepository.save(buildTestStaffMember(
          id: 'staff-1',
          roles: {StaffRole.staff},
          status: StaffMemberStatus.suspended));
      final repository = DevelopmentStaffAuthRepository(
        staffMemberRepository: memberRepository,
        sessionDuration: () => const Duration(hours: 1),
      );

      final session = await repository.signIn(staffMemberId: 'staff-1');

      expect(session, isNull);
    });

    test('signIn denies a member with no roles at all', () async {
      final memberRepository = InMemoryStaffMemberRepository();
      await memberRepository.save(buildTestStaffMember(id: 'staff-1'));
      final repository = DevelopmentStaffAuthRepository(
        staffMemberRepository: memberRepository,
        sessionDuration: () => const Duration(hours: 1),
      );

      final session = await repository.signIn(staffMemberId: 'staff-1');

      expect(session, isNull);
    });

    test(
        'refreshSession reflects a role removed since the session was '
        'issued', () async {
      final memberRepository = InMemoryStaffMemberRepository();
      await memberRepository.save(buildTestStaffMember(
          id: 'staff-1', roles: {StaffRole.staff, StaffRole.manager}));
      final repository = DevelopmentStaffAuthRepository(
        staffMemberRepository: memberRepository,
        sessionDuration: () => const Duration(hours: 1),
      );
      final original = await repository.signIn(staffMemberId: 'staff-1');

      // The role is removed out-of-band (simulating AssignStaffRole/
      // RevokeStaffRole having run elsewhere).
      final member = await memberRepository.findById('staff-1');
      await memberRepository.save(member!.copyWith(
        roles: {StaffRole.staff},
        revision: member.revision + 1,
      ));

      final refreshed = await repository.refreshSession(original!);

      expect(refreshed, isNotNull);
      expect(refreshed!.roles, {StaffRole.staff});
    });

    test(
        'refreshSession denies a session issued before a forced '
        'revocation', () async {
      final memberRepository = InMemoryStaffMemberRepository();
      await memberRepository.save(
          buildTestStaffMember(id: 'staff-1', roles: {StaffRole.manager}));
      final repository = DevelopmentStaffAuthRepository(
        staffMemberRepository: memberRepository,
        sessionDuration: () => const Duration(hours: 1),
      );
      final original = await repository.signIn(staffMemberId: 'staff-1');
      await Future<void>.delayed(const Duration(milliseconds: 5));

      final member = await memberRepository.findById('staff-1');
      await memberRepository.save(member!.copyWith(
        sessionsRevokedAt: DateTime.now(),
        revision: member.revision + 1,
      ));

      final refreshed = await repository.refreshSession(original!);

      expect(refreshed, isNull);
    });

    test('refreshSession denies once the member becomes suspended', () async {
      final memberRepository = InMemoryStaffMemberRepository();
      await memberRepository
          .save(buildTestStaffMember(id: 'staff-1', roles: {StaffRole.staff}));
      final repository = DevelopmentStaffAuthRepository(
        staffMemberRepository: memberRepository,
        sessionDuration: () => const Duration(hours: 1),
      );
      final original = await repository.signIn(staffMemberId: 'staff-1');

      final member = await memberRepository.findById('staff-1');
      await memberRepository.save(member!.copyWith(
        status: StaffMemberStatus.suspended,
        revision: member.revision + 1,
      ));

      final refreshed = await repository.refreshSession(original!);

      expect(refreshed, isNull);
    });
  });

  group('ProductionUnavailableStaffAuthRepository', () {
    test(
        'signIn always denies — "do not claim production backend '
        'validation if none exists"', () async {
      const repository = ProductionUnavailableStaffAuthRepository();

      final session = await repository.signIn(staffMemberId: 'staff-1');

      expect(session, isNull);
    });
  });
}
