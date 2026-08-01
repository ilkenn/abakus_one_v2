import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/admin/application/identity/branch_id_generator.dart';
import 'package:abakus_one_v2/features/admin/application/identity/organization_id_generator.dart';
import 'package:abakus_one_v2/features/admin/application/identity/restaurant_id_generator.dart';
import 'package:abakus_one_v2/features/admin/application/use_cases/create_branch.dart';
import 'package:abakus_one_v2/features/admin/application/use_cases/create_organization.dart';
import 'package:abakus_one_v2/features/admin/application/use_cases/create_restaurant.dart';
import 'package:abakus_one_v2/features/admin/application/use_cases/set_branch_emergency_stop.dart';
import 'package:abakus_one_v2/features/admin/application/use_cases/set_branch_status.dart';
import 'package:abakus_one_v2/features/admin/data/admin_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/admin/data/branch_repository.dart';
import 'package:abakus_one_v2/features/admin/data/organization_repository.dart';
import 'package:abakus_one_v2/features/admin/data/restaurant_repository.dart';
import 'package:abakus_one_v2/features/admin/domain/organization/branch.dart';
import 'package:abakus_one_v2/features/admin/domain/organization/branch_status.dart';
import 'package:abakus_one_v2/features/admin/domain/organization/organization.dart';
import 'package:abakus_one_v2/features/admin/domain/organization/restaurant.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/actor_session.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/real_pos_authorization_policy.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/staff_role.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/admin_test_fixtures.dart';

Branch _buildTestBranch({
  String id = 'branch-1',
  String restaurantId = 'restaurant-1',
  BranchStatus status = BranchStatus.active,
  bool emergencyStopped = false,
}) {
  return Branch(
    id: id,
    restaurantId: restaurantId,
    name: 'Test Şube',
    status: status,
    emergencyStopped: emergencyStopped,
    createdAt: DateTime(2026, 1, 1),
    revision: 1,
  );
}

void main() {
  group('CreateOrganization', () {
    test('creates an organization', () async {
      final repository = InMemoryOrganizationRepository();
      final useCase = CreateOrganization(
        authorizationPolicy: const AllowAllAdminPolicy(),
        idGenerator: SequentialOrganizationIdGenerator(),
        repository: repository,
        auditRepository: InMemoryAdminAuditEntryRepository(),
      );

      final org = await useCase(
        name: 'Abaküs',
        performedByStaffId: 'admin-1',
        createdAt: DateTime(2026, 1, 1),
      );

      expect(await repository.findById(org.id), org);
    });

    test('an unauthorized actor cannot create an organization', () async {
      final useCase = CreateOrganization(
        authorizationPolicy: const DenyAllAdminPolicy(),
        idGenerator: SequentialOrganizationIdGenerator(),
        repository: InMemoryOrganizationRepository(),
        auditRepository: InMemoryAdminAuditEntryRepository(),
      );

      expect(
        () => useCase(
          name: 'Abaküs',
          performedByStaffId: 'manager-1',
          createdAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
    });
  });

  group('CreateRestaurant', () {
    test('creates a restaurant under an existing organization', () async {
      final orgRepository = InMemoryOrganizationRepository(seed: [
        Organization(
          id: 'org-1',
          name: 'Abaküs',
          createdAt: DateTime(2026, 1, 1),
          revision: 1,
        ),
      ]);
      final restaurantRepository = InMemoryRestaurantRepository();
      final useCase = CreateRestaurant(
        authorizationPolicy: const AllowAllAdminPolicy(),
        idGenerator: SequentialRestaurantIdGenerator(),
        repository: restaurantRepository,
        organizationRepository: orgRepository,
        auditRepository: InMemoryAdminAuditEntryRepository(),
      );

      final restaurant = await useCase(
        organizationId: 'org-1',
        name: 'Abaküs Bowl',
        performedByStaffId: 'admin-1',
        createdAt: DateTime(2026, 1, 1),
      );

      expect(restaurant.organizationId, 'org-1');
      expect(await restaurantRepository.findById(restaurant.id), restaurant);
    });

    test('an unknown organization id throws', () async {
      final useCase = CreateRestaurant(
        authorizationPolicy: const AllowAllAdminPolicy(),
        idGenerator: SequentialRestaurantIdGenerator(),
        repository: InMemoryRestaurantRepository(),
        organizationRepository: InMemoryOrganizationRepository(),
        auditRepository: InMemoryAdminAuditEntryRepository(),
      );

      expect(
        () => useCase(
          organizationId: 'missing',
          name: 'Abaküs Bowl',
          performedByStaffId: 'admin-1',
          createdAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<UnknownAdminEntityViolation>()),
      );
    });
  });

  group('CreateBranch', () {
    test('creates a branch under an existing restaurant', () async {
      final restaurantRepository = InMemoryRestaurantRepository(seed: [
        Restaurant(
          id: 'restaurant-1',
          organizationId: 'org-1',
          name: 'Abaküs Bowl',
          createdAt: DateTime(2026, 1, 1),
          revision: 1,
        ),
      ]);
      final branchRepository = InMemoryBranchRepository();
      final useCase = CreateBranch(
        authorizationPolicy: const AllowAllAdminPolicy(),
        idGenerator: SequentialBranchIdGenerator(),
        repository: branchRepository,
        restaurantRepository: restaurantRepository,
        auditRepository: InMemoryAdminAuditEntryRepository(),
      );

      final branch = await useCase(
        restaurantId: 'restaurant-1',
        name: 'Merkez Şube',
        performedByStaffId: 'admin-1',
        createdAt: DateTime(2026, 1, 1),
      );

      expect(branch.restaurantId, 'restaurant-1');
      expect(branch.status, BranchStatus.active);
    });

    test('an unknown restaurant id throws', () async {
      final useCase = CreateBranch(
        authorizationPolicy: const AllowAllAdminPolicy(),
        idGenerator: SequentialBranchIdGenerator(),
        repository: InMemoryBranchRepository(),
        restaurantRepository: InMemoryRestaurantRepository(),
        auditRepository: InMemoryAdminAuditEntryRepository(),
      );

      expect(
        () => useCase(
          restaurantId: 'missing',
          name: 'Merkez Şube',
          performedByStaffId: 'admin-1',
          createdAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<UnknownAdminEntityViolation>()),
      );
    });
  });

  group('SetBranchStatus', () {
    test('archived is terminal', () async {
      final repository = InMemoryBranchRepository(
        seed: [_buildTestBranch(status: BranchStatus.archived)],
      );
      final useCase = SetBranchStatus(
        authorizationPolicy: const AllowAllAdminPolicy(),
        repository: repository,
        auditRepository: InMemoryAdminAuditEntryRepository(),
      );

      expect(
        () => useCase(
          branchId: 'branch-1',
          newStatus: BranchStatus.active,
          performedByStaffId: 'admin-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<BranchArchivedViolation>()),
      );
    });

    test('changes status and records an AdminAuditEntry', () async {
      final repository = InMemoryBranchRepository(seed: [_buildTestBranch()]);
      final auditRepository = InMemoryAdminAuditEntryRepository();
      final useCase = SetBranchStatus(
        authorizationPolicy: const AllowAllAdminPolicy(),
        repository: repository,
        auditRepository: auditRepository,
      );

      final updated = await useCase(
        branchId: 'branch-1',
        newStatus: BranchStatus.inactive,
        performedByStaffId: 'admin-1',
        performedAt: DateTime(2026, 1, 1),
      );

      expect(updated.status, BranchStatus.inactive);
      expect(
          await auditRepository.findByTargetEntityId('branch-1'), hasLength(1));
    });

    test(
        'Phase 6P: a manager without access to the branch is denied end '
        '-to-end through RealPosAuthorizationPolicy', () async {
      final repository = InMemoryBranchRepository(seed: [_buildTestBranch()]);
      const session = ActorSession(
        actorId: 'manager-1',
        roles: {StaffRole.manager},
        activeRole: StaffRole.manager,
        branchAccess: {'branch-2'},
      );
      final useCase = SetBranchStatus(
        authorizationPolicy: RealPosAuthorizationPolicy(
          currentSession: () => session,
        ),
        repository: repository,
        auditRepository: InMemoryAdminAuditEntryRepository(),
      );

      expect(
        () => useCase(
          branchId: 'branch-1',
          newStatus: BranchStatus.inactive,
          performedByStaffId: 'manager-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
    });

    test(
        'Phase 6P: a manager granted access to the branch succeeds '
        'end-to-end through RealPosAuthorizationPolicy', () async {
      final repository = InMemoryBranchRepository(seed: [_buildTestBranch()]);
      const session = ActorSession(
        actorId: 'manager-1',
        roles: {StaffRole.manager},
        activeRole: StaffRole.manager,
        branchAccess: {'branch-1'},
      );
      final useCase = SetBranchStatus(
        authorizationPolicy: RealPosAuthorizationPolicy(
          currentSession: () => session,
        ),
        repository: repository,
        auditRepository: InMemoryAdminAuditEntryRepository(),
      );

      final updated = await useCase(
        branchId: 'branch-1',
        newStatus: BranchStatus.inactive,
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 1),
      );

      expect(updated.status, BranchStatus.inactive);
    });
  });

  group('SetBranchEmergencyStop', () {
    test('triggers and clears an emergency stop', () async {
      final repository = InMemoryBranchRepository(seed: [_buildTestBranch()]);
      final useCase = SetBranchEmergencyStop(
        authorizationPolicy: const AllowAllAdminPolicy(),
        repository: repository,
        auditRepository: InMemoryAdminAuditEntryRepository(),
      );

      final stopped = await useCase(
        branchId: 'branch-1',
        stopped: true,
        performedByStaffId: 'admin-1',
        performedAt: DateTime(2026, 1, 1),
      );
      expect(stopped.emergencyStopped, isTrue);

      final cleared = await useCase(
        branchId: 'branch-1',
        stopped: false,
        performedByStaffId: 'admin-1',
        performedAt: DateTime(2026, 1, 2),
      );
      expect(cleared.emergencyStopped, isFalse);
    });

    test('an unauthorized actor cannot trigger an emergency stop', () async {
      final repository = InMemoryBranchRepository(seed: [_buildTestBranch()]);
      final useCase = SetBranchEmergencyStop(
        authorizationPolicy: const DenyAllAdminPolicy(),
        repository: repository,
        auditRepository: InMemoryAdminAuditEntryRepository(),
      );

      expect(
        () => useCase(
          branchId: 'branch-1',
          stopped: true,
          performedByStaffId: 'manager-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
    });
  });
}
