import 'package:abakus_one_v2/bootstrap/app_environment.dart';
import 'package:abakus_one_v2/core/config/app_environment_config.dart';
import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/platform/application/use_cases/build_release_readiness_snapshot.dart';
import 'package:abakus_one_v2/features/platform/domain/authorization/platform_actor_session.dart';
import 'package:abakus_one_v2/features/platform/domain/authorization/platform_role.dart';
import 'package:abakus_one_v2/features/platform/domain/authorization/real_platform_authorization_policy.dart';
import 'package:abakus_one_v2/features/platform/domain/release_readiness_criterion_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BuildReleaseReadinessSnapshot', () {
    test('reports the real, honest criteria for the injected environment',
        () async {
      const session = PlatformActorSession(
        actorId: 'platform-1',
        roles: {PlatformRole.platformOwner},
        activeRole: PlatformRole.platformOwner,
      );
      final useCase = BuildReleaseReadinessSnapshot(
        authorizationPolicy:
            RealPlatformAuthorizationPolicy(currentSession: () => session),
        environmentConfig: AppEnvironmentConfig.staging,
      );

      final snapshot = await useCase(actorId: 'platform-1');

      expect(snapshot.environment, AppEnvironment.staging);
      expect(snapshot.criteria, isNotEmpty);
      expect(
        snapshot.criteria.map((c) => c.key),
        containsAll(<String>[
          'environmentSeparation',
          'crashReporting',
          'remoteConfigFeatureFlags',
          'appVersionObservability',
          'platformMonitoring',
          'integrationAuditTrail',
        ]),
      );
    });

    test('is not release-ready today — crash reporting is a real gap',
        () async {
      const session = PlatformActorSession(
        actorId: 'platform-1',
        roles: {PlatformRole.platformOwner},
        activeRole: PlatformRole.platformOwner,
      );
      final useCase = BuildReleaseReadinessSnapshot(
        authorizationPolicy:
            RealPlatformAuthorizationPolicy(currentSession: () => session),
        environmentConfig: AppEnvironmentConfig.production,
      );

      final snapshot = await useCase(actorId: 'platform-1');

      expect(snapshot.isReleaseReady, isFalse);
      expect(
        snapshot.blockingCriteria.map((c) => c.key),
        contains('crashReporting'),
      );
      final crashReporting =
          snapshot.criteria.firstWhere((c) => c.key == 'crashReporting');
      expect(crashReporting.status, ReleaseReadinessCriterionStatus.notReady);
    });

    test('an unauthorized actor is denied', () async {
      final useCase = BuildReleaseReadinessSnapshot(
        authorizationPolicy:
            RealPlatformAuthorizationPolicy(currentSession: () => null),
        environmentConfig: AppEnvironmentConfig.production,
      );

      expect(
        () => useCase(actorId: 'platform-1'),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
    });

    test(
        'a platformAdministrator (not just owner) can view release '
        'readiness — administrator-tier action', () async {
      const session = PlatformActorSession(
        actorId: 'admin-1',
        roles: {PlatformRole.platformAdministrator},
        activeRole: PlatformRole.platformAdministrator,
      );
      final useCase = BuildReleaseReadinessSnapshot(
        authorizationPolicy:
            RealPlatformAuthorizationPolicy(currentSession: () => session),
        environmentConfig: AppEnvironmentConfig.development,
      );

      final snapshot = await useCase(actorId: 'admin-1');

      expect(snapshot.environment, AppEnvironment.development);
    });
  });
}
