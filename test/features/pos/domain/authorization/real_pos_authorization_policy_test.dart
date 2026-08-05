import 'package:abakus_one_v2/features/pos/domain/authorization/actor_session.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/pos_authorized_action.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/real_pos_authorization_policy.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/staff_role.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RealPosAuthorizationPolicy', () {
    test('no active session denies', () async {
      final policy = RealPosAuthorizationPolicy(currentSession: () => null);

      final result = await policy.authorize(
        action: PosAuthorizedAction.reopenOrder,
        actorStaffId: 'staff-1',
      );

      expect(result.granted, isFalse);
      expect(result.reason, 'No active session');
    });

    test(
        'an actorStaffId not matching the active session denies '
        '("unknown actor")', () async {
      const session = ActorSession(
        actorId: 'staff-1',
        roles: {StaffRole.admin},
        activeRole: StaffRole.admin,
      );
      final policy = RealPosAuthorizationPolicy(currentSession: () => session);

      final result = await policy.authorize(
        action: PosAuthorizedAction.voidPayment,
        actorStaffId: 'someone-else',
      );

      expect(result.granted, isFalse);
      expect(result.reason, 'Unknown actor');
    });

    test('a role without the requested permission denies', () async {
      const session = ActorSession(
        actorId: 'staff-1',
        roles: {StaffRole.staff},
        activeRole: StaffRole.staff,
      );
      final policy = RealPosAuthorizationPolicy(currentSession: () => session);

      final result = await policy.authorize(
        action: PosAuthorizedAction.voidPayment,
        actorStaffId: 'staff-1',
      );

      expect(result.granted, isFalse);
    });

    test('a manager-authorized action is allowed', () async {
      const session = ActorSession(
        actorId: 'manager-1',
        roles: {StaffRole.manager},
        activeRole: StaffRole.manager,
      );
      final policy = RealPosAuthorizationPolicy(currentSession: () => session);

      final result = await policy.authorize(
        action: PosAuthorizedAction.manageVisitRewardRules,
        actorStaffId: 'manager-1',
      );

      expect(result.granted, isTrue);
    });

    test('an admin-authorized action is allowed', () async {
      const session = ActorSession(
        actorId: 'admin-1',
        roles: {StaffRole.admin},
        activeRole: StaffRole.admin,
      );
      final policy = RealPosAuthorizationPolicy(currentSession: () => session);

      final result = await policy.authorize(
        action: PosAuthorizedAction.voidPayment,
        actorStaffId: 'admin-1',
      );

      expect(result.granted, isTrue);
    });

    test('a courier cannot perform a manager action', () async {
      const session = ActorSession(
        actorId: 'courier-1',
        roles: {StaffRole.courier},
        activeRole: StaffRole.courier,
      );
      final policy = RealPosAuthorizationPolicy(currentSession: () => session);

      final result = await policy.authorize(
        action: PosAuthorizedAction.manuallyAssignDelivery,
        actorStaffId: 'courier-1',
      );

      expect(result.granted, isFalse);
    });

    test('staff cannot perform an admin action', () async {
      const session = ActorSession(
        actorId: 'staff-1',
        roles: {StaffRole.staff},
        activeRole: StaffRole.staff,
      );
      final policy = RealPosAuthorizationPolicy(currentSession: () => session);

      final result = await policy.authorize(
        action: PosAuthorizedAction.correctPayment,
        actorStaffId: 'staff-1',
      );

      expect(result.granted, isFalse);
    });

    test('a multi-role actor is granted the union of both roles\' actions',
        () async {
      const session = ActorSession(
        actorId: 'dual-1',
        roles: {StaffRole.courier, StaffRole.manager},
        activeRole: StaffRole.courier,
      );
      final policy = RealPosAuthorizationPolicy(currentSession: () => session);

      final courierResult = await policy.authorize(
        action: PosAuthorizedAction.completeDelivery,
        actorStaffId: 'dual-1',
      );
      final managerResult = await policy.authorize(
        action: PosAuthorizedAction.manuallyAssignDelivery,
        actorStaffId: 'dual-1',
      );

      expect(courierResult.granted, isTrue);
      expect(managerResult.granted, isTrue);
    });

    test(
        'role switching changes what is granted for the active-role-scoped '
        'check without losing union-based authorization', () async {
      const session = ActorSession(
        actorId: 'dual-1',
        roles: {StaffRole.courier, StaffRole.manager},
        activeRole: StaffRole.courier,
      );
      ActorSession current = session;
      final policy = RealPosAuthorizationPolicy(currentSession: () => current);

      // Full authorize() always grants by the union, regardless of active role.
      final beforeSwitch = await policy.authorize(
        action: PosAuthorizedAction.manuallyAssignDelivery,
        actorStaffId: 'dual-1',
      );
      expect(beforeSwitch.granted, isTrue);

      current = current.withActiveRole(StaffRole.manager);

      final afterSwitch = await policy.authorize(
        action: PosAuthorizedAction.completeDelivery,
        actorStaffId: 'dual-1',
      );
      expect(afterSwitch.granted, isTrue); // still granted - union-based
    });

    test('a null session built from malformed raw data denies safely',
        () async {
      final session = ActorSession.tryFromRaw(
        actorId: 'staff-1',
        roleNames: ['not-a-real-role'],
      );
      final policy = RealPosAuthorizationPolicy(currentSession: () => session);

      final result = await policy.authorize(
        action: PosAuthorizedAction.acknowledgeKitchenItem,
        actorStaffId: 'staff-1',
      );

      expect(session, isNull);
      expect(result.granted, isFalse);
    });

    test('a revoked session denies even with a permitted role (Phase 6B)',
        () async {
      const session = ActorSession(
        actorId: 'admin-1',
        roles: {StaffRole.admin},
        activeRole: StaffRole.admin,
        revoked: true,
      );
      final policy = RealPosAuthorizationPolicy(currentSession: () => session);

      final result = await policy.authorize(
        action: PosAuthorizedAction.voidPayment,
        actorStaffId: 'admin-1',
      );

      expect(result.granted, isFalse);
      expect(result.reason, 'Session revoked');
    });

    test('an expired session denies even with a permitted role (Phase 6B)',
        () async {
      final session = ActorSession(
        actorId: 'admin-1',
        roles: const {StaffRole.admin},
        activeRole: StaffRole.admin,
        expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      final policy = RealPosAuthorizationPolicy(currentSession: () => session);

      final result = await policy.authorize(
        action: PosAuthorizedAction.voidPayment,
        actorStaffId: 'admin-1',
      );

      expect(result.granted, isFalse);
      expect(result.reason, 'Session expired');
    });

    group('branch scoping (Phase 6P)', () {
      test(
          'a manager without branch access is denied a branch-scoped '
          'action even though their role permits it', () async {
        const session = ActorSession(
          actorId: 'manager-1',
          roles: {StaffRole.manager},
          activeRole: StaffRole.manager,
        );
        final policy =
            RealPosAuthorizationPolicy(currentSession: () => session);

        final result = await policy.authorize(
          action: PosAuthorizedAction.manageBranch,
          actorStaffId: 'manager-1',
          context: const {kBranchIdAuthorizationContextKey: 'branch-1'},
        );

        expect(result.granted, isFalse);
        expect(result.reason, contains('branch-1'));
      });

      test('a manager granted access to the target branch is allowed',
          () async {
        const session = ActorSession(
          actorId: 'manager-1',
          roles: {StaffRole.manager},
          activeRole: StaffRole.manager,
          branchAccess: {'branch-1'},
        );
        final policy =
            RealPosAuthorizationPolicy(currentSession: () => session);

        final result = await policy.authorize(
          action: PosAuthorizedAction.manageBranch,
          actorStaffId: 'manager-1',
          context: const {kBranchIdAuthorizationContextKey: 'branch-1'},
        );

        expect(result.granted, isTrue);
      });

      test(
          'a manager granted access to a different branch is denied for '
          'the target branch', () async {
        const session = ActorSession(
          actorId: 'manager-1',
          roles: {StaffRole.manager},
          activeRole: StaffRole.manager,
          branchAccess: {'branch-2'},
        );
        final policy =
            RealPosAuthorizationPolicy(currentSession: () => session);

        final result = await policy.authorize(
          action: PosAuthorizedAction.manageBranch,
          actorStaffId: 'manager-1',
          context: const {kBranchIdAuthorizationContextKey: 'branch-1'},
        );

        expect(result.granted, isFalse);
      });

      test('admin is exempt from branch scoping — org-wide oversight role',
          () async {
        const session = ActorSession(
          actorId: 'admin-1',
          roles: {StaffRole.admin},
          activeRole: StaffRole.admin,
        );
        final policy =
            RealPosAuthorizationPolicy(currentSession: () => session);

        final result = await policy.authorize(
          action: PosAuthorizedAction.manageBranch,
          actorStaffId: 'admin-1',
          context: const {kBranchIdAuthorizationContextKey: 'branch-1'},
        );

        expect(result.granted, isTrue);
      });

      test(
          'an action with no branchId in context is unaffected by branch '
          'scoping, even with empty branchAccess', () async {
        const session = ActorSession(
          actorId: 'manager-1',
          roles: {StaffRole.manager},
          activeRole: StaffRole.manager,
        );
        final policy =
            RealPosAuthorizationPolicy(currentSession: () => session);

        final result = await policy.authorize(
          action: PosAuthorizedAction.manageBranch,
          actorStaffId: 'manager-1',
        );

        expect(result.granted, isTrue);
      });

      test(
          'tenantOwner is exempt from branch scoping, same as admin '
          '(Phase 8)', () async {
        const session = ActorSession(
          actorId: 'owner-1',
          roles: {StaffRole.tenantOwner},
          activeRole: StaffRole.tenantOwner,
        );
        final policy =
            RealPosAuthorizationPolicy(currentSession: () => session);

        final result = await policy.authorize(
          action: PosAuthorizedAction.manageBranch,
          actorStaffId: 'owner-1',
          context: const {kBranchIdAuthorizationContextKey: 'branch-1'},
        );

        expect(result.granted, isTrue);
      });
    });

    group('organization scoping (Phase 8)', () {
      test(
          'admin without organization access is denied an '
          'organization-scoped action — no role is exempt', () async {
        const session = ActorSession(
          actorId: 'admin-1',
          roles: {StaffRole.admin},
          activeRole: StaffRole.admin,
        );
        final policy =
            RealPosAuthorizationPolicy(currentSession: () => session);

        final result = await policy.authorize(
          action: PosAuthorizedAction.manageOrganization,
          actorStaffId: 'admin-1',
          context: const {kOrganizationIdAuthorizationContextKey: 'org-1'},
        );

        expect(result.granted, isFalse);
        expect(result.reason, contains('org-1'));
      });

      test(
          'tenantOwner without organization access is denied — not even '
          'the most senior tenant role is exempt', () async {
        const session = ActorSession(
          actorId: 'owner-1',
          roles: {StaffRole.tenantOwner},
          activeRole: StaffRole.tenantOwner,
        );
        final policy =
            RealPosAuthorizationPolicy(currentSession: () => session);

        final result = await policy.authorize(
          action: PosAuthorizedAction.manageTenantBranding,
          actorStaffId: 'owner-1',
          context: const {kOrganizationIdAuthorizationContextKey: 'org-1'},
        );

        expect(result.granted, isFalse);
      });

      test('a manager granted access to the target organization is allowed',
          () async {
        const session = ActorSession(
          actorId: 'manager-1',
          roles: {StaffRole.manager},
          activeRole: StaffRole.manager,
          organizationAccess: {'org-1'},
        );
        final policy =
            RealPosAuthorizationPolicy(currentSession: () => session);

        final result = await policy.authorize(
          action: PosAuthorizedAction.manageBranch,
          actorStaffId: 'manager-1',
          context: const {kOrganizationIdAuthorizationContextKey: 'org-1'},
        );

        expect(result.granted, isTrue);
      });

      test(
          'an actor granted access to a different organization is denied '
          'for the target organization', () async {
        const session = ActorSession(
          actorId: 'admin-1',
          roles: {StaffRole.admin},
          activeRole: StaffRole.admin,
          organizationAccess: {'org-2'},
        );
        final policy =
            RealPosAuthorizationPolicy(currentSession: () => session);

        final result = await policy.authorize(
          action: PosAuthorizedAction.manageOrganization,
          actorStaffId: 'admin-1',
          context: const {kOrganizationIdAuthorizationContextKey: 'org-1'},
        );

        expect(result.granted, isFalse);
      });

      test(
          'an action with no organizationId in context is unaffected, even '
          'with empty organizationAccess', () async {
        const session = ActorSession(
          actorId: 'admin-1',
          roles: {StaffRole.admin},
          activeRole: StaffRole.admin,
        );
        final policy =
            RealPosAuthorizationPolicy(currentSession: () => session);

        final result = await policy.authorize(
          action: PosAuthorizedAction.manageOrganization,
          actorStaffId: 'admin-1',
        );

        expect(result.granted, isTrue);
      });
    });

    group('restaurant scoping (Phase 9)', () {
      test(
          'a restaurant id resolved to an organization the actor lacks '
          'access to is denied', () async {
        const session = ActorSession(
          actorId: 'admin-1',
          roles: {StaffRole.admin},
          activeRole: StaffRole.admin,
          organizationAccess: {'org-2'},
        );
        final policy = RealPosAuthorizationPolicy(
          currentSession: () => session,
          resolveRestaurantOrganizationId: (restaurantId) async =>
              restaurantId == 'restaurant-1' ? 'org-1' : null,
        );

        final result = await policy.authorize(
          action: PosAuthorizedAction.manageRestaurant,
          actorStaffId: 'admin-1',
          context: const {
            kRestaurantIdAuthorizationContextKey: 'restaurant-1',
          },
        );

        expect(result.granted, isFalse);
        expect(result.reason, contains('org-1'));
      });

      test(
          'a restaurant id resolved to an organization the actor holds is '
          'allowed', () async {
        const session = ActorSession(
          actorId: 'manager-1',
          roles: {StaffRole.manager},
          activeRole: StaffRole.manager,
          organizationAccess: {'org-1'},
        );
        final policy = RealPosAuthorizationPolicy(
          currentSession: () => session,
          resolveRestaurantOrganizationId: (restaurantId) async =>
              restaurantId == 'restaurant-1' ? 'org-1' : null,
        );

        final result = await policy.authorize(
          action: PosAuthorizedAction.manageBranch,
          actorStaffId: 'manager-1',
          context: const {
            kRestaurantIdAuthorizationContextKey: 'restaurant-1',
          },
        );

        expect(result.granted, isTrue);
      });

      test(
          'no role is exempt from restaurant scoping, mirroring '
          'organization scoping — admin without access is still denied',
          () async {
        const session = ActorSession(
          actorId: 'admin-1',
          roles: {StaffRole.admin},
          activeRole: StaffRole.admin,
        );
        final policy = RealPosAuthorizationPolicy(
          currentSession: () => session,
          resolveRestaurantOrganizationId: (restaurantId) async => 'org-1',
        );

        final result = await policy.authorize(
          action: PosAuthorizedAction.manageOrganization,
          actorStaffId: 'admin-1',
          context: const {
            kRestaurantIdAuthorizationContextKey: 'restaurant-1',
          },
        );

        expect(result.granted, isFalse);
      });

      test(
          'no resolver wired at all denies (fail closed), never silently '
          'skips the check', () async {
        const session = ActorSession(
          actorId: 'admin-1',
          roles: {StaffRole.admin},
          activeRole: StaffRole.admin,
          organizationAccess: {'org-1'},
        );
        final policy =
            RealPosAuthorizationPolicy(currentSession: () => session);

        final result = await policy.authorize(
          action: PosAuthorizedAction.manageOrganization,
          actorStaffId: 'admin-1',
          context: const {
            kRestaurantIdAuthorizationContextKey: 'restaurant-1',
          },
        );

        expect(result.granted, isFalse);
      });

      test(
          'an unresolvable restaurant id (resolver returns null) denies, '
          'never silently skips the check', () async {
        const session = ActorSession(
          actorId: 'admin-1',
          roles: {StaffRole.admin},
          activeRole: StaffRole.admin,
          organizationAccess: {'org-1'},
        );
        final policy = RealPosAuthorizationPolicy(
          currentSession: () => session,
          resolveRestaurantOrganizationId: (restaurantId) async => null,
        );

        final result = await policy.authorize(
          action: PosAuthorizedAction.manageOrganization,
          actorStaffId: 'admin-1',
          context: const {
            kRestaurantIdAuthorizationContextKey: 'unknown-restaurant',
          },
        );

        expect(result.granted, isFalse);
      });

      test('an action with no restaurantId in context is unaffected', () async {
        const session = ActorSession(
          actorId: 'admin-1',
          roles: {StaffRole.admin},
          activeRole: StaffRole.admin,
        );
        final policy =
            RealPosAuthorizationPolicy(currentSession: () => session);

        final result = await policy.authorize(
          action: PosAuthorizedAction.manageOrganization,
          actorStaffId: 'admin-1',
        );

        expect(result.granted, isTrue);
      });
    });
  });
}
