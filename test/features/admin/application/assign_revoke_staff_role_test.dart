import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/admin/application/identity/staff_role_change_event_id_generator.dart';
import 'package:abakus_one_v2/features/admin/application/use_cases/assign_staff_role.dart';
import 'package:abakus_one_v2/features/admin/application/use_cases/revoke_staff_role.dart';
import 'package:abakus_one_v2/features/admin/data/admin_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/admin/data/staff_member_repository.dart';
import 'package:abakus_one_v2/features/admin/data/staff_role_change_event_repository.dart';
import 'package:abakus_one_v2/features/admin/domain/staff/staff_member_status.dart';
import 'package:abakus_one_v2/features/admin/domain/staff/staff_role_change_event.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/authorization_result.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/pos_authorization_policy.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/pos_authorized_action.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/staff_role.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/admin_test_fixtures.dart';

void main() {
  group('AssignStaffRole', () {
    test('grants a role, additive to any existing roles', () async {
      final repository = InMemoryStaffMemberRepository();
      await repository
          .save(buildTestStaffMember(id: 'target-1', roles: {StaffRole.staff}));
      final useCase = AssignStaffRole(
        authorizationPolicy: const AllowAllAdminPolicy(),
        repository: repository,
        roleChangeEventRepository: InMemoryStaffRoleChangeEventRepository(),
        idGenerator: SequentialStaffRoleChangeEventIdGenerator(),
        auditRepository: InMemoryAdminAuditEntryRepository(),
      );

      final updated = await useCase(
        staffMemberId: 'target-1',
        role: StaffRole.manager,
        performedByStaffId: 'admin-1',
        performedAt: DateTime(2026, 1, 1),
      );

      expect(updated.roles, {StaffRole.staff, StaffRole.manager});
    });

    test('self-promotion is never allowed, regardless of authorization',
        () async {
      final repository = InMemoryStaffMemberRepository();
      await repository.save(buildTestStaffMember(id: 'admin-1'));
      final useCase = AssignStaffRole(
        authorizationPolicy: const AllowAllAdminPolicy(),
        repository: repository,
        roleChangeEventRepository: InMemoryStaffRoleChangeEventRepository(),
        idGenerator: SequentialStaffRoleChangeEventIdGenerator(),
        auditRepository: InMemoryAdminAuditEntryRepository(),
      );

      expect(
        () => useCase(
          staffMemberId: 'admin-1',
          role: StaffRole.admin,
          performedByStaffId: 'admin-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<SelfRoleGrantNotAllowedViolation>()),
      );
    });

    test(
        'granting the admin role requires manageStaffAdminRole, denied by '
        'a policy that only grants manageStaffRoles', () async {
      final repository = InMemoryStaffMemberRepository();
      await repository.save(buildTestStaffMember(id: 'target-1'));
      final useCase = AssignStaffRole(
        authorizationPolicy: const _ManagerOnlyPolicy(),
        repository: repository,
        roleChangeEventRepository: InMemoryStaffRoleChangeEventRepository(),
        idGenerator: SequentialStaffRoleChangeEventIdGenerator(),
        auditRepository: InMemoryAdminAuditEntryRepository(),
      );

      expect(
        () => useCase(
          staffMemberId: 'target-1',
          role: StaffRole.admin,
          performedByStaffId: 'manager-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
    });

    test('an unknown staff member id throws UnknownAdminEntityViolation',
        () async {
      final useCase = AssignStaffRole(
        authorizationPolicy: const AllowAllAdminPolicy(),
        repository: InMemoryStaffMemberRepository(),
        roleChangeEventRepository: InMemoryStaffRoleChangeEventRepository(),
        idGenerator: SequentialStaffRoleChangeEventIdGenerator(),
        auditRepository: InMemoryAdminAuditEntryRepository(),
      );

      expect(
        () => useCase(
          staffMemberId: 'missing',
          role: StaffRole.staff,
          performedByStaffId: 'admin-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<UnknownAdminEntityViolation>()),
      );
    });

    test('a suspended staff member cannot receive a new role', () async {
      final repository = InMemoryStaffMemberRepository();
      await repository.save(buildTestStaffMember(
          id: 'target-1', status: StaffMemberStatus.suspended));
      final useCase = AssignStaffRole(
        authorizationPolicy: const AllowAllAdminPolicy(),
        repository: repository,
        roleChangeEventRepository: InMemoryStaffRoleChangeEventRepository(),
        idGenerator: SequentialStaffRoleChangeEventIdGenerator(),
        auditRepository: InMemoryAdminAuditEntryRepository(),
      );

      expect(
        () => useCase(
          staffMemberId: 'target-1',
          role: StaffRole.staff,
          performedByStaffId: 'admin-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<StaffMemberNotActiveViolation>()),
      );
    });

    test('records a StaffRoleChangeEvent and an AdminAuditEntry', () async {
      final repository = InMemoryStaffMemberRepository();
      await repository.save(buildTestStaffMember(id: 'target-1'));
      final roleChangeRepository = InMemoryStaffRoleChangeEventRepository();
      final auditRepository = InMemoryAdminAuditEntryRepository();
      final useCase = AssignStaffRole(
        authorizationPolicy: const AllowAllAdminPolicy(),
        repository: repository,
        roleChangeEventRepository: roleChangeRepository,
        idGenerator: SequentialStaffRoleChangeEventIdGenerator(),
        auditRepository: auditRepository,
      );

      await useCase(
        staffMemberId: 'target-1',
        role: StaffRole.manager,
        performedByStaffId: 'admin-1',
        performedAt: DateTime(2026, 1, 1),
      );

      final events = await roleChangeRepository.findByStaffMemberId('target-1');
      expect(events.single.changeType, StaffRoleChangeType.granted);
      final entries = await auditRepository.findByTargetEntityId('target-1');
      expect(entries, hasLength(1));
    });
  });

  group('RevokeStaffRole', () {
    test('removes a held role', () async {
      final repository = InMemoryStaffMemberRepository();
      await repository.save(buildTestStaffMember(
          id: 'target-1', roles: {StaffRole.staff, StaffRole.manager}));
      final useCase = RevokeStaffRole(
        authorizationPolicy: const AllowAllAdminPolicy(),
        repository: repository,
        roleChangeEventRepository: InMemoryStaffRoleChangeEventRepository(),
        idGenerator: SequentialStaffRoleChangeEventIdGenerator(),
        auditRepository: InMemoryAdminAuditEntryRepository(),
      );

      final updated = await useCase(
        staffMemberId: 'target-1',
        role: StaffRole.manager,
        performedByStaffId: 'admin-1',
        performedAt: DateTime(2026, 1, 1),
      );

      expect(updated.roles, {StaffRole.staff});
    });

    test('self-revocation is never allowed either', () async {
      final repository = InMemoryStaffMemberRepository();
      await repository
          .save(buildTestStaffMember(id: 'admin-1', roles: {StaffRole.admin}));
      final useCase = RevokeStaffRole(
        authorizationPolicy: const AllowAllAdminPolicy(),
        repository: repository,
        roleChangeEventRepository: InMemoryStaffRoleChangeEventRepository(),
        idGenerator: SequentialStaffRoleChangeEventIdGenerator(),
        auditRepository: InMemoryAdminAuditEntryRepository(),
      );

      expect(
        () => useCase(
          staffMemberId: 'admin-1',
          role: StaffRole.admin,
          performedByStaffId: 'admin-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<SelfRoleGrantNotAllowedViolation>()),
      );
    });

    test('revoking a role the member never held is a no-op, no event',
        () async {
      final repository = InMemoryStaffMemberRepository();
      await repository
          .save(buildTestStaffMember(id: 'target-1', roles: {StaffRole.staff}));
      final auditRepository = InMemoryAdminAuditEntryRepository();
      final useCase = RevokeStaffRole(
        authorizationPolicy: const AllowAllAdminPolicy(),
        repository: repository,
        roleChangeEventRepository: InMemoryStaffRoleChangeEventRepository(),
        idGenerator: SequentialStaffRoleChangeEventIdGenerator(),
        auditRepository: auditRepository,
      );

      final result = await useCase(
        staffMemberId: 'target-1',
        role: StaffRole.manager,
        performedByStaffId: 'admin-1',
        performedAt: DateTime(2026, 1, 1),
      );

      expect(result.roles, {StaffRole.staff});
      expect(await auditRepository.findByTargetEntityId('target-1'), isEmpty);
    });
  });
}

/// Grants everything except `manageStaffAdminRole` — for proving
/// "granting the admin role requires manageStaffAdminRole specifically."
class _ManagerOnlyPolicy implements PosAuthorizationPolicy {
  const _ManagerOnlyPolicy();

  @override
  Future<AuthorizationResult> authorize({
    required PosAuthorizedAction action,
    required String actorStaffId,
    Map<String, String> context = const {},
  }) async {
    if (action == PosAuthorizedAction.manageStaffAdminRole) {
      return const AuthorizationResult(granted: false);
    }
    return const AuthorizationResult(granted: true);
  }
}
