import 'package:abakus_one_v2/features/pos/domain/authorization/actor_session.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/staff_role.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ActorSession.tryFromRaw', () {
    test('builds a session from valid role names', () {
      final session = ActorSession.tryFromRaw(
        actorId: 'staff-1',
        roleNames: ['manager', 'courier'],
      );

      expect(session, isNotNull);
      expect(session!.roles, {StaffRole.manager, StaffRole.courier});
    });

    test('a blank actorId denies safely (returns null)', () {
      final session = ActorSession.tryFromRaw(
        actorId: '   ',
        roleNames: ['manager'],
      );

      expect(session, isNull);
    });

    test('unknown role names are silently dropped, never thrown', () {
      final session = ActorSession.tryFromRaw(
        actorId: 'staff-1',
        roleNames: ['manager', 'super-admin-9000'],
      );

      expect(session, isNotNull);
      expect(session!.roles, {StaffRole.manager});
    });

    test('malformed role data (nothing recognized) denies safely', () {
      final session = ActorSession.tryFromRaw(
        actorId: 'staff-1',
        roleNames: ['not-a-role', 'also-not-a-role'],
      );

      expect(session, isNull);
    });

    test('an activeRoleName the actor does not hold denies safely', () {
      final session = ActorSession.tryFromRaw(
        actorId: 'staff-1',
        roleNames: ['staff'],
        activeRoleName: 'admin',
      );

      expect(session, isNull);
    });

    test('defaults activeRole to the first recognized role when omitted', () {
      final session = ActorSession.tryFromRaw(
        actorId: 'staff-1',
        roleNames: ['courier'],
      );

      expect(session!.activeRole, StaffRole.courier);
    });
  });

  group('ActorSession.withActiveRole', () {
    test('switches the active role among roles the actor holds', () {
      const session = ActorSession(
        actorId: 'staff-1',
        roles: {StaffRole.manager, StaffRole.courier},
        activeRole: StaffRole.manager,
      );

      final switched = session.withActiveRole(StaffRole.courier);

      expect(switched.activeRole, StaffRole.courier);
      expect(switched.roles, session.roles);
      expect(switched.actorId, session.actorId);
    });

    test('throws when switching to a role the actor does not hold', () {
      const session = ActorSession(
        actorId: 'staff-1',
        roles: {StaffRole.staff},
        activeRole: StaffRole.staff,
      );

      expect(
        () => session.withActiveRole(StaffRole.admin),
        throwsArgumentError,
      );
    });
  });

  group('ActorSession — Phase 6B validity/scope', () {
    test('isExpired is false when expiresAt is null', () {
      const session = ActorSession(
        actorId: 'staff-1',
        roles: {StaffRole.staff},
        activeRole: StaffRole.staff,
      );

      expect(session.isExpired, isFalse);
      expect(session.isValid, isTrue);
    });

    test('isExpired is true once expiresAt has passed', () {
      final session = ActorSession(
        actorId: 'staff-1',
        roles: const {StaffRole.staff},
        activeRole: StaffRole.staff,
        expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );

      expect(session.isExpired, isTrue);
      expect(session.isValid, isFalse);
    });

    test('isValid is false when revoked, even if not expired', () {
      final session = ActorSession(
        actorId: 'staff-1',
        roles: const {StaffRole.staff},
        activeRole: StaffRole.staff,
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        revoked: true,
      );

      expect(session.isValid, isFalse);
    });

    test('hasBranchAccess reflects branchAccess membership', () {
      const session = ActorSession(
        actorId: 'staff-1',
        roles: {StaffRole.manager},
        activeRole: StaffRole.manager,
        branchAccess: {'branch-1', 'branch-2'},
      );

      expect(session.hasBranchAccess('branch-1'), isTrue);
      expect(session.hasBranchAccess('branch-3'), isFalse);
    });

    test('withActiveBranch switches among granted branches', () {
      const session = ActorSession(
        actorId: 'staff-1',
        roles: {StaffRole.manager},
        activeRole: StaffRole.manager,
        branchAccess: {'branch-1', 'branch-2'},
      );

      final switched = session.withActiveBranch('branch-2');

      expect(switched.activeBranchId, 'branch-2');
      expect(switched.roles, session.roles);
    });

    test('withActiveBranch throws for a branch not in branchAccess', () {
      const session = ActorSession(
        actorId: 'staff-1',
        roles: {StaffRole.manager},
        activeRole: StaffRole.manager,
        branchAccess: {'branch-1'},
      );

      expect(
        () => session.withActiveBranch('branch-9'),
        throwsArgumentError,
      );
    });

    test(
        'tryFromRaw carries branch access and denies an unheld '
        'activeBranchId', () {
      final granted = ActorSession.tryFromRaw(
        actorId: 'staff-1',
        roleNames: ['manager'],
        branchAccessIds: ['branch-1', 'branch-2'],
        activeBranchId: 'branch-2',
      );
      expect(granted, isNotNull);
      expect(granted!.branchAccess, {'branch-1', 'branch-2'});
      expect(granted.activeBranchId, 'branch-2');

      final denied = ActorSession.tryFromRaw(
        actorId: 'staff-1',
        roleNames: ['manager'],
        branchAccessIds: ['branch-1'],
        activeBranchId: 'branch-9',
      );
      expect(denied, isNull);
    });
  });
}
