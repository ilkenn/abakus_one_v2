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
}
