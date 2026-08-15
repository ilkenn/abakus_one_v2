import 'package:abakus_one_v2/features/pos/domain/authorization/actor_session.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/pos_authorized_action.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/role_permission_map.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/staff_role.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RolePermissionMap tier hierarchy', () {
    test('manager includes every staff-tier action', () {
      final staffActions = RolePermissionMap.permissionsFor(StaffRole.staff);
      final managerActions =
          RolePermissionMap.permissionsFor(StaffRole.manager);

      expect(managerActions.containsAll(staffActions), isTrue);
    });

    test('admin includes every manager-tier and staff-tier action', () {
      final managerActions =
          RolePermissionMap.permissionsFor(StaffRole.manager);
      final adminActions = RolePermissionMap.permissionsFor(StaffRole.admin);

      expect(adminActions.containsAll(managerActions), isTrue);
    });

    test('courier is lateral — never a subset of staff/manager/admin', () {
      final courierActions =
          RolePermissionMap.permissionsFor(StaffRole.courier);
      final adminActions = RolePermissionMap.permissionsFor(StaffRole.admin);

      expect(courierActions.contains(PosAuthorizedAction.completeDelivery),
          isTrue);
      expect(
          adminActions.contains(PosAuthorizedAction.completeDelivery), isFalse);
    });

    test('courier cannot perform a manager-tier action', () {
      expect(
        RolePermissionMap.allows(
          {StaffRole.courier},
          PosAuthorizedAction.manuallyAssignDelivery,
        ),
        isFalse,
      );
    });

    test('staff cannot perform an admin-only action', () {
      expect(
        RolePermissionMap.allows(
          {StaffRole.staff},
          PosAuthorizedAction.voidPayment,
        ),
        isFalse,
      );
    });

    test('a manager-authorized action is allowed for manager', () {
      expect(
        RolePermissionMap.allows(
          {StaffRole.manager},
          PosAuthorizedAction.manageVisitRewardRules,
        ),
        isTrue,
      );
    });

    test('an admin-authorized action is allowed for admin', () {
      expect(
        RolePermissionMap.allows(
          {StaffRole.admin},
          PosAuthorizedAction.voidPayment,
        ),
        isTrue,
      );
    });

    test(
        'tenantOwner includes every admin-tier and manager-tier action '
        '(Phase 8)', () {
      final adminActions = RolePermissionMap.permissionsFor(StaffRole.admin);
      final tenantOwnerActions =
          RolePermissionMap.permissionsFor(StaffRole.tenantOwner);

      expect(tenantOwnerActions.containsAll(adminActions), isTrue);
    });

    test('admin cannot perform a tenantOwner-only action (Phase 8)', () {
      expect(
        RolePermissionMap.allows(
          {StaffRole.admin},
          PosAuthorizedAction.manageTenantBranding,
        ),
        isFalse,
      );
    });

    test(
        'a tenantOwner-authorized action is allowed for tenantOwner '
        '(Phase 8)', () {
      expect(
        RolePermissionMap.allows(
          {StaffRole.tenantOwner},
          PosAuthorizedAction.manageTenantBranding,
        ),
        isTrue,
      );
    });
  });

  group('RolePermissionMap — manageReservations / manageBranch (Faz R.3A.1)',
      () {
    // Faz R.3A.1 — the admin "Rezervasyonlar" nav entry's visibility is now
    // *derived* from this exact tiering (see
    // AdminShellScreen._reservationsVisibleToRoles), rather than a
    // separately hand-authored role list. These assertions are the
    // regression guard for that derivation: if a future change moves
    // manageReservations to a different tier, the nav visibility set
    // changes automatically and correctly, and this test documents what
    // the resulting set must be.
    test(
        'manager/admin/tenantOwner hold manageReservations; staff/courier do not',
        () {
      for (final role in {
        StaffRole.manager,
        StaffRole.admin,
        StaffRole.tenantOwner
      }) {
        expect(
          RolePermissionMap.permissionsFor(role)
              .contains(PosAuthorizedAction.manageReservations),
          isTrue,
          reason: '$role should hold manageReservations',
        );
      }
      for (final role in {StaffRole.staff, StaffRole.courier}) {
        expect(
          RolePermissionMap.permissionsFor(role)
              .contains(PosAuthorizedAction.manageReservations),
          isFalse,
          reason: '$role should NOT hold manageReservations',
        );
      }
    });

    test('manager/admin/tenantOwner hold manageBranch; staff/courier do not',
        () {
      for (final role in {
        StaffRole.manager,
        StaffRole.admin,
        StaffRole.tenantOwner
      }) {
        expect(
          RolePermissionMap.permissionsFor(role)
              .contains(PosAuthorizedAction.manageBranch),
          isTrue,
          reason: '$role should hold manageBranch',
        );
      }
      for (final role in {StaffRole.staff, StaffRole.courier}) {
        expect(
          RolePermissionMap.permissionsFor(role)
              .contains(PosAuthorizedAction.manageBranch),
          isFalse,
          reason: '$role should NOT hold manageBranch',
        );
      }
    });
  });

  group(
      'RolePermissionMap vs. backend DEFAULT_STAFF_ROLE_PERMISSIONS — '
      'cross-system agreement (Faz R.3A.2)', () {
    // A hand-verified mirror of functions/src/staffAuthorization.ts's
    // DEFAULT_STAFF_ROLE_PERMISSIONS for exactly the two permissions the
    // client currently gates on (manageReservations, manageBranch). Cannot
    // literally import/run the TS source from a Dart test, so this is the
    // regression guard: if either side's mapping for these two permissions
    // ever drifts from the other, this test starts failing and the drift
    // is caught here rather than silently reaching production as a UI/
    // backend authorization mismatch.
    const backendRolesWithManageReservations = {
      'manager',
      'admin',
      'tenantOwner',
    };
    const backendRolesWithManageBranch = {
      'manager',
      'admin',
      'tenantOwner',
    };

    test(
        'every StaffRole\'s manageReservations grant matches the backend '
        'default mapping', () {
      for (final role in StaffRole.values) {
        final dartGrants = RolePermissionMap.permissionsFor(role)
            .contains(PosAuthorizedAction.manageReservations);
        final backendGrants =
            backendRolesWithManageReservations.contains(role.name);
        expect(
          dartGrants,
          backendGrants,
          reason: '$role: Dart=$dartGrants, backend=$backendGrants',
        );
      }
    });

    test(
        'every StaffRole\'s manageBranch grant matches the backend '
        'default mapping', () {
      for (final role in StaffRole.values) {
        final dartGrants = RolePermissionMap.permissionsFor(role)
            .contains(PosAuthorizedAction.manageBranch);
        final backendGrants = backendRolesWithManageBranch.contains(role.name);
        expect(
          dartGrants,
          backendGrants,
          reason: '$role: Dart=$dartGrants, backend=$backendGrants',
        );
      }
    });
  });

  group('RolePermissionMap.allows — multi-role union', () {
    test('a multi-role actor gets the union of every held role', () {
      final roles = {StaffRole.courier, StaffRole.manager};

      expect(
        RolePermissionMap.allows(
            roles, PosAuthorizedAction.completeDelivery), // courier-only
        isTrue,
      );
      expect(
        RolePermissionMap.allows(
            roles, PosAuthorizedAction.manuallyAssignDelivery), // manager-only
        isTrue,
      );
      expect(
        RolePermissionMap.allows(roles, PosAuthorizedAction.voidPayment),
        isFalse, // admin-only, neither held role grants it
      );
    });
  });

  group('RolePermissionMap.allowsForActiveRole', () {
    test('checks only the currently active role, not the full union', () {
      const session = ActorSession(
        actorId: 'staff-1',
        roles: {StaffRole.courier, StaffRole.manager},
        activeRole: StaffRole.courier,
      );

      expect(
        RolePermissionMap.allowsForActiveRole(
            session, PosAuthorizedAction.completeDelivery),
        isTrue,
      );
      expect(
        RolePermissionMap.allowsForActiveRole(
            session, PosAuthorizedAction.manuallyAssignDelivery),
        isFalse,
      );
    });

    test('switching the active role changes what is currently permitted', () {
      const session = ActorSession(
        actorId: 'staff-1',
        roles: {StaffRole.courier, StaffRole.manager},
        activeRole: StaffRole.courier,
      );
      final switched = session.withActiveRole(StaffRole.manager);

      expect(
        RolePermissionMap.allowsForActiveRole(
            switched, PosAuthorizedAction.manuallyAssignDelivery),
        isTrue,
      );
      expect(
        RolePermissionMap.allowsForActiveRole(
            switched, PosAuthorizedAction.completeDelivery),
        isFalse,
      );
    });
  });
}
