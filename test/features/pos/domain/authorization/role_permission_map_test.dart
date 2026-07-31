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
