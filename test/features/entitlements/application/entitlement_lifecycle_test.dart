import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/core/services/feature_flags/feature_flags_keys.dart';
import 'package:abakus_one_v2/features/entitlements/application/use_cases/check_module_access.dart';
import 'package:abakus_one_v2/features/entitlements/application/use_cases/grant_module_entitlement.dart';
import 'package:abakus_one_v2/features/entitlements/application/use_cases/set_entitlement_status.dart';
import 'package:abakus_one_v2/features/entitlements/application/identity/entitlement_grant_id_generator.dart';
import 'package:abakus_one_v2/features/entitlements/data/entitlement_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/entitlements/data/entitlement_grant_repository.dart';
import 'package:abakus_one_v2/features/entitlements/domain/entitlement_grant.dart';
import 'package:abakus_one_v2/features/entitlements/domain/entitlement_module.dart';
import 'package:abakus_one_v2/features/entitlements/domain/entitlement_scope_type.dart';
import 'package:abakus_one_v2/features/entitlements/domain/entitlement_status.dart';
import 'package:abakus_one_v2/features/entitlements/domain/module_access_denial_reason.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/entitlement_test_fixtures.dart';

void main() {
  group('GrantModuleEntitlement', () {
    test('grants a module for a scope', () async {
      final repository = InMemoryEntitlementGrantRepository();
      final useCase = GrantModuleEntitlement(
        authorizationPolicy: const AllowAllEntitlementPolicy(),
        idGenerator: SequentialEntitlementGrantIdGenerator(),
        repository: repository,
        auditRepository: InMemoryEntitlementAuditEntryRepository(),
      );

      final grant = await useCase(
        module: EntitlementModule.inventory,
        scopeType: EntitlementScopeType.branch,
        scopeId: 'branch-1',
        performedByStaffId: 'admin-1',
        performedAt: DateTime(2026, 1, 1),
      );

      expect(grant.status, EntitlementStatus.trial);
      expect(
        await repository.findByModuleAndScope(
          EntitlementModule.inventory,
          EntitlementScopeType.branch,
          'branch-1',
        ),
        isNotNull,
      );
    });

    test('an unauthorized actor cannot grant a module', () async {
      final useCase = GrantModuleEntitlement(
        authorizationPolicy: const DenyAllEntitlementPolicy(),
        idGenerator: SequentialEntitlementGrantIdGenerator(),
        repository: InMemoryEntitlementGrantRepository(),
        auditRepository: InMemoryEntitlementAuditEntryRepository(),
      );

      expect(
        () => useCase(
          module: EntitlementModule.inventory,
          scopeType: EntitlementScopeType.branch,
          scopeId: 'branch-1',
          performedByStaffId: 'manager-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
    });
  });

  group('SetEntitlementStatus', () {
    test('changes status to revoked', () async {
      final repository = InMemoryEntitlementGrantRepository(seed: [
        EntitlementGrant(
          id: 'grant-1',
          module: EntitlementModule.inventory,
          scopeType: EntitlementScopeType.branch,
          scopeId: 'branch-1',
          status: EntitlementStatus.active,
          grantedByStaffId: 'admin-1',
          grantedAt: DateTime(2026, 1, 1),
          revision: 1,
        ),
      ]);
      final useCase = SetEntitlementStatus(
        authorizationPolicy: const AllowAllEntitlementPolicy(),
        repository: repository,
        auditRepository: InMemoryEntitlementAuditEntryRepository(),
      );

      final updated = await useCase(
        grantId: 'grant-1',
        newStatus: EntitlementStatus.revoked,
        performedByStaffId: 'admin-1',
        performedAt: DateTime(2026, 1, 2),
      );

      expect(updated.status, EntitlementStatus.revoked);
    });

    test('an unknown grant id throws', () async {
      final useCase = SetEntitlementStatus(
        authorizationPolicy: const AllowAllEntitlementPolicy(),
        repository: InMemoryEntitlementGrantRepository(),
        auditRepository: InMemoryEntitlementAuditEntryRepository(),
      );

      expect(
        () => useCase(
          grantId: 'missing',
          newStatus: EntitlementStatus.revoked,
          performedByStaffId: 'admin-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<UnknownEntitlementGrantViolation>()),
      );
    });
  });

  group('EntitlementGrant.isCurrentlyEntitled', () {
    test('active with no date bounds is always entitled', () {
      final grant = EntitlementGrant(
        id: 'g1',
        module: EntitlementModule.inventory,
        scopeType: EntitlementScopeType.branch,
        scopeId: 'branch-1',
        status: EntitlementStatus.active,
        grantedByStaffId: 'admin-1',
        grantedAt: DateTime(2026, 1, 1),
        revision: 1,
      );

      expect(grant.isCurrentlyEntitled(DateTime(2030, 1, 1)), isTrue);
    });

    test('expired status is never entitled, even within date range', () {
      final grant = EntitlementGrant(
        id: 'g1',
        module: EntitlementModule.inventory,
        scopeType: EntitlementScopeType.branch,
        scopeId: 'branch-1',
        status: EntitlementStatus.expired,
        startsAt: DateTime(2026, 1, 1),
        expiresAt: DateTime(2030, 1, 1),
        grantedByStaffId: 'admin-1',
        grantedAt: DateTime(2026, 1, 1),
        revision: 1,
      );

      expect(grant.isCurrentlyEntitled(DateTime(2027, 1, 1)), isFalse);
    });

    test('a future-dated startsAt is not yet entitled', () {
      final grant = EntitlementGrant(
        id: 'g1',
        module: EntitlementModule.inventory,
        scopeType: EntitlementScopeType.branch,
        scopeId: 'branch-1',
        status: EntitlementStatus.active,
        startsAt: DateTime(2030, 1, 1),
        grantedByStaffId: 'admin-1',
        grantedAt: DateTime(2026, 1, 1),
        revision: 1,
      );

      expect(grant.isCurrentlyEntitled(DateTime(2027, 1, 1)), isFalse);
    });
  });

  group('CheckModuleAccess', () {
    test('denies notEntitled when no grant exists', () async {
      final useCase = CheckModuleAccess(
        entitlementRepository: InMemoryEntitlementGrantRepository(),
        featureFlagsService: FakeFeatureFlagsService(
          enabledKeys: {FeatureFlagsKeys.inventoryEnabled},
        ),
        authorizationPolicy: const AllowAllEntitlementPolicy(),
      );

      final result = await useCase(
        module: EntitlementModule.inventory,
        scopeType: EntitlementScopeType.branch,
        scopeId: 'branch-1',
        actorStaffId: 'manager-1',
      );

      expect(result.isGranted, isFalse);
      expect(result.denialReason, ModuleAccessDenialReason.notEntitled);
    });

    test('denies featureDisabled when entitled but flag is off', () async {
      final entitlementRepository = InMemoryEntitlementGrantRepository(seed: [
        EntitlementGrant(
          id: 'g1',
          module: EntitlementModule.inventory,
          scopeType: EntitlementScopeType.branch,
          scopeId: 'branch-1',
          status: EntitlementStatus.active,
          grantedByStaffId: 'admin-1',
          grantedAt: DateTime(2026, 1, 1),
          revision: 1,
        ),
      ]);
      final useCase = CheckModuleAccess(
        entitlementRepository: entitlementRepository,
        featureFlagsService: FakeFeatureFlagsService(),
        authorizationPolicy: const AllowAllEntitlementPolicy(),
      );

      final result = await useCase(
        module: EntitlementModule.inventory,
        scopeType: EntitlementScopeType.branch,
        scopeId: 'branch-1',
        actorStaffId: 'manager-1',
      );

      expect(result.denialReason, ModuleAccessDenialReason.featureDisabled);
    });

    test(
        'denies permissionDenied when entitled and enabled but actor lacks '
        'the role', () async {
      final entitlementRepository = InMemoryEntitlementGrantRepository(seed: [
        EntitlementGrant(
          id: 'g1',
          module: EntitlementModule.inventory,
          scopeType: EntitlementScopeType.branch,
          scopeId: 'branch-1',
          status: EntitlementStatus.active,
          grantedByStaffId: 'admin-1',
          grantedAt: DateTime(2026, 1, 1),
          revision: 1,
        ),
      ]);
      final useCase = CheckModuleAccess(
        entitlementRepository: entitlementRepository,
        featureFlagsService: FakeFeatureFlagsService(
          enabledKeys: {FeatureFlagsKeys.inventoryEnabled},
        ),
        authorizationPolicy: const DenyAllEntitlementPolicy(),
      );

      final result = await useCase(
        module: EntitlementModule.inventory,
        scopeType: EntitlementScopeType.branch,
        scopeId: 'branch-1',
        actorStaffId: 'staff-1',
      );

      expect(result.denialReason, ModuleAccessDenialReason.permissionDenied);
    });

    test('grants access when all three layers agree', () async {
      final entitlementRepository = InMemoryEntitlementGrantRepository(seed: [
        EntitlementGrant(
          id: 'g1',
          module: EntitlementModule.inventory,
          scopeType: EntitlementScopeType.branch,
          scopeId: 'branch-1',
          status: EntitlementStatus.active,
          grantedByStaffId: 'admin-1',
          grantedAt: DateTime(2026, 1, 1),
          revision: 1,
        ),
      ]);
      final useCase = CheckModuleAccess(
        entitlementRepository: entitlementRepository,
        featureFlagsService: FakeFeatureFlagsService(
          enabledKeys: {FeatureFlagsKeys.inventoryEnabled},
        ),
        authorizationPolicy: const AllowAllEntitlementPolicy(),
      );

      final result = await useCase(
        module: EntitlementModule.inventory,
        scopeType: EntitlementScopeType.branch,
        scopeId: 'branch-1',
        actorStaffId: 'manager-1',
      );

      expect(result.isGranted, isTrue);
      expect(result.denialReason, isNull);
    });
  });
}
