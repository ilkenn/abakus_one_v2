import 'package:abakus_one_v2/features/platform/domain/authorization/platform_actor_session.dart';
import 'package:abakus_one_v2/features/platform/domain/authorization/platform_role.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PlatformActorSession.tryFromRaw', () {
    test('builds a session from valid role names', () {
      final session = PlatformActorSession.tryFromRaw(
        actorId: 'platform-1',
        roleNames: ['platformOwner'],
      );

      expect(session, isNotNull);
      expect(session!.roles, {PlatformRole.platformOwner});
    });

    test('a blank actorId denies safely (returns null)', () {
      final session = PlatformActorSession.tryFromRaw(
        actorId: '   ',
        roleNames: ['platformOwner'],
      );

      expect(session, isNull);
    });

    test('malformed role data (nothing recognized) denies safely', () {
      final session = PlatformActorSession.tryFromRaw(
        actorId: 'platform-1',
        roleNames: ['not-a-role'],
      );

      expect(session, isNull);
    });

    test('an activeRoleName the actor does not hold denies safely', () {
      final session = PlatformActorSession.tryFromRaw(
        actorId: 'platform-1',
        roleNames: ['platformAdministrator'],
        activeRoleName: 'platformOwner',
      );

      expect(session, isNull);
    });

    test('defaults activeRole to the first recognized role when omitted', () {
      final session = PlatformActorSession.tryFromRaw(
        actorId: 'platform-1',
        roleNames: ['platformAdministrator'],
      );

      expect(session, isNotNull);
      expect(session!.activeRole, PlatformRole.platformAdministrator);
    });
  });

  group('PlatformActorSession.withActiveRole', () {
    test('switches to a held role', () {
      const session = PlatformActorSession(
        actorId: 'platform-1',
        roles: {PlatformRole.platformAdministrator, PlatformRole.platformOwner},
        activeRole: PlatformRole.platformAdministrator,
      );

      final switched = session.withActiveRole(PlatformRole.platformOwner);

      expect(switched.activeRole, PlatformRole.platformOwner);
    });

    test('throws when switching to a role not held', () {
      const session = PlatformActorSession(
        actorId: 'platform-1',
        roles: {PlatformRole.platformAdministrator},
        activeRole: PlatformRole.platformAdministrator,
      );

      expect(
        () => session.withActiveRole(PlatformRole.platformOwner),
        throwsArgumentError,
      );
    });
  });

  group('PlatformActorSession.isValid', () {
    test('a fresh session with no expiry is valid', () {
      const session = PlatformActorSession(
        actorId: 'platform-1',
        roles: {PlatformRole.platformOwner},
        activeRole: PlatformRole.platformOwner,
      );

      expect(session.isValid, isTrue);
    });

    test('a revoked session is invalid', () {
      const session = PlatformActorSession(
        actorId: 'platform-1',
        roles: {PlatformRole.platformOwner},
        activeRole: PlatformRole.platformOwner,
        revoked: true,
      );

      expect(session.isValid, isFalse);
    });

    test('an expired session is invalid', () {
      final session = PlatformActorSession(
        actorId: 'platform-1',
        roles: const {PlatformRole.platformOwner},
        activeRole: PlatformRole.platformOwner,
        expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );

      expect(session.isValid, isFalse);
    });
  });
}
