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
  });
}
