import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/platform/application/use_cases/build_store_compliance_snapshot.dart';
import 'package:abakus_one_v2/features/platform/domain/authorization/platform_actor_session.dart';
import 'package:abakus_one_v2/features/platform/domain/authorization/platform_role.dart';
import 'package:abakus_one_v2/features/platform/domain/authorization/real_platform_authorization_policy.dart';
import 'package:abakus_one_v2/features/platform/domain/store_compliance_criterion_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BuildStoreComplianceSnapshot', () {
    test('reports the real, honest store-compliance criteria', () async {
      const session = PlatformActorSession(
        actorId: 'platform-1',
        roles: {PlatformRole.platformOwner},
        activeRole: PlatformRole.platformOwner,
      );
      final useCase = BuildStoreComplianceSnapshot(
        authorizationPolicy:
            RealPlatformAuthorizationPolicy(currentSession: () => session),
      );

      final snapshot = await useCase(actorId: 'platform-1');

      expect(
        snapshot.criteria.map((c) => c.key),
        containsAll(<String>[
          'accountDeletion',
          'dataExport',
          'privacyPolicyDocument',
          'termsOfUseDocument',
          'dataSafetyDeclaration',
        ]),
      );
    });

    test('is not store-compliant today — account deletion is a real gap',
        () async {
      const session = PlatformActorSession(
        actorId: 'platform-1',
        roles: {PlatformRole.platformOwner},
        activeRole: PlatformRole.platformOwner,
      );
      final useCase = BuildStoreComplianceSnapshot(
        authorizationPolicy:
            RealPlatformAuthorizationPolicy(currentSession: () => session),
      );

      final snapshot = await useCase(actorId: 'platform-1');

      expect(snapshot.isStoreCompliant, isFalse);
      expect(
        snapshot.blockingCriteria.map((c) => c.key),
        contains('accountDeletion'),
      );
      final accountDeletion =
          snapshot.criteria.firstWhere((c) => c.key == 'accountDeletion');
      expect(accountDeletion.status, StoreComplianceCriterionStatus.notReady);
    });

    test('an unauthorized actor is denied', () async {
      final useCase = BuildStoreComplianceSnapshot(
        authorizationPolicy:
            RealPlatformAuthorizationPolicy(currentSession: () => null),
      );

      expect(
        () => useCase(actorId: 'platform-1'),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
    });

    test(
        'a platformAdministrator (not just owner) can view store '
        'compliance — administrator-tier action', () async {
      const session = PlatformActorSession(
        actorId: 'admin-1',
        roles: {PlatformRole.platformAdministrator},
        activeRole: PlatformRole.platformAdministrator,
      );
      final useCase = BuildStoreComplianceSnapshot(
        authorizationPolicy:
            RealPlatformAuthorizationPolicy(currentSession: () => session),
      );

      final snapshot = await useCase(actorId: 'admin-1');

      expect(snapshot.criteria, isNotEmpty);
    });
  });
}
