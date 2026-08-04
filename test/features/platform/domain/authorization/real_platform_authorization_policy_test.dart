import 'package:abakus_one_v2/features/platform/domain/authorization/platform_actor_session.dart';
import 'package:abakus_one_v2/features/platform/domain/authorization/platform_authorized_action.dart';
import 'package:abakus_one_v2/features/platform/domain/authorization/platform_role.dart';
import 'package:abakus_one_v2/features/platform/domain/authorization/real_platform_authorization_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RealPlatformAuthorizationPolicy', () {
    test('no active session denies', () async {
      final policy =
          RealPlatformAuthorizationPolicy(currentSession: () => null);

      final result = await policy.authorize(
        action: PlatformAuthorizedAction.viewPlatformAuditCenter,
        actorId: 'platform-1',
      );

      expect(result.granted, isFalse);
      expect(result.reason, 'No active platform session');
    });

    test('an actorId not matching the active session denies', () async {
      const session = PlatformActorSession(
        actorId: 'platform-1',
        roles: {PlatformRole.platformOwner},
        activeRole: PlatformRole.platformOwner,
      );
      final policy =
          RealPlatformAuthorizationPolicy(currentSession: () => session);

      final result = await policy.authorize(
        action: PlatformAuthorizedAction.manageTenantOrganizations,
        actorId: 'someone-else',
      );

      expect(result.granted, isFalse);
      expect(result.reason, 'Unknown actor');
    });

    test(
        'a platformAdministrator without the requested permission is '
        'denied an owner-only action', () async {
      const session = PlatformActorSession(
        actorId: 'platform-admin-1',
        roles: {PlatformRole.platformAdministrator},
        activeRole: PlatformRole.platformAdministrator,
      );
      final policy =
          RealPlatformAuthorizationPolicy(currentSession: () => session);

      final result = await policy.authorize(
        action: PlatformAuthorizedAction.manageTenantOrganizations,
        actorId: 'platform-admin-1',
      );

      expect(result.granted, isFalse);
    });

    test('a platformAdministrator-tier action is allowed', () async {
      const session = PlatformActorSession(
        actorId: 'platform-admin-1',
        roles: {PlatformRole.platformAdministrator},
        activeRole: PlatformRole.platformAdministrator,
      );
      final policy =
          RealPlatformAuthorizationPolicy(currentSession: () => session);

      final result = await policy.authorize(
        action: PlatformAuthorizedAction.viewPlatformAuditCenter,
        actorId: 'platform-admin-1',
      );

      expect(result.granted, isTrue);
    });

    test('a platformOwner-authorized action is allowed', () async {
      const session = PlatformActorSession(
        actorId: 'owner-1',
        roles: {PlatformRole.platformOwner},
        activeRole: PlatformRole.platformOwner,
      );
      final policy =
          RealPlatformAuthorizationPolicy(currentSession: () => session);

      final result = await policy.authorize(
        action: PlatformAuthorizedAction.manageTenantOrganizations,
        actorId: 'owner-1',
      );

      expect(result.granted, isTrue);
    });

    test('a null session built from malformed raw data denies safely',
        () async {
      final session = PlatformActorSession.tryFromRaw(
        actorId: 'platform-1',
        roleNames: ['not-a-real-role'],
      );
      final policy =
          RealPlatformAuthorizationPolicy(currentSession: () => session);

      final result = await policy.authorize(
        action: PlatformAuthorizedAction.viewPlatformAuditCenter,
        actorId: 'platform-1',
      );

      expect(session, isNull);
      expect(result.granted, isFalse);
    });

    test('a revoked session denies even with a permitted role', () async {
      const session = PlatformActorSession(
        actorId: 'owner-1',
        roles: {PlatformRole.platformOwner},
        activeRole: PlatformRole.platformOwner,
        revoked: true,
      );
      final policy =
          RealPlatformAuthorizationPolicy(currentSession: () => session);

      final result = await policy.authorize(
        action: PlatformAuthorizedAction.manageTenantOrganizations,
        actorId: 'owner-1',
      );

      expect(result.granted, isFalse);
      expect(result.reason, 'Session revoked');
    });

    test('an expired session denies even with a permitted role', () async {
      final session = PlatformActorSession(
        actorId: 'owner-1',
        roles: const {PlatformRole.platformOwner},
        activeRole: PlatformRole.platformOwner,
        expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      final policy =
          RealPlatformAuthorizationPolicy(currentSession: () => session);

      final result = await policy.authorize(
        action: PlatformAuthorizedAction.manageTenantOrganizations,
        actorId: 'owner-1',
      );

      expect(result.granted, isFalse);
      expect(result.reason, 'Session expired');
    });

    test('a multi-role actor is granted the union of both roles\' actions',
        () async {
      const session = PlatformActorSession(
        actorId: 'dual-1',
        roles: {
          PlatformRole.platformAdministrator,
          PlatformRole.platformOwner,
        },
        activeRole: PlatformRole.platformAdministrator,
      );
      final policy =
          RealPlatformAuthorizationPolicy(currentSession: () => session);

      final ownerResult = await policy.authorize(
        action: PlatformAuthorizedAction.manageTenantOrganizations,
        actorId: 'dual-1',
      );
      final adminResult = await policy.authorize(
        action: PlatformAuthorizedAction.viewPlatformAuditCenter,
        actorId: 'dual-1',
      );

      expect(ownerResult.granted, isTrue);
      expect(adminResult.granted, isTrue);
    });
  });
}
