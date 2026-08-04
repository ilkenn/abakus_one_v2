import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/integrations/application/identity/integration_credential_ref_id_generator.dart';
import 'package:abakus_one_v2/features/integrations/application/use_cases/revoke_integration_credential.dart';
import 'package:abakus_one_v2/features/integrations/application/use_cases/store_integration_credential.dart';
import 'package:abakus_one_v2/features/integrations/data/integration_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/integrations/data/integration_credential_ref_repository.dart';
import 'package:abakus_one_v2/features/integrations/domain/audit/integration_audit_event_type.dart';
import 'package:abakus_one_v2/features/integrations/domain/integration_credential_kind.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/fake_integration_credential_storage.dart';
import '../test_support/integration_test_fixtures.dart';

void main() {
  group('StoreIntegrationCredential', () {
    test(
        'writes the value to storage and never exposes it in the ref or '
        'audit entry', () async {
      final storage = FakeIntegrationCredentialStorage();
      final refRepository = InMemoryIntegrationCredentialRefRepository();
      final auditRepository = InMemoryIntegrationAuditEntryRepository();
      final useCase = StoreIntegrationCredential(
        authorizationPolicy: const AllowAllIntegrationPolicy(),
        storage: storage,
        idGenerator: SequentialIntegrationCredentialRefIdGenerator(),
        repository: refRepository,
        auditRepository: auditRepository,
      );

      final ref = await useCase(
        organizationId: 'org-1',
        providerId: 'iyzico',
        kind: IntegrationCredentialKind.apiKey,
        value: 'super-secret-key-value',
        performedByStaffId: 'owner-1',
        performedAt: DateTime(2026, 1, 1),
      );

      expect(await storage.readValue(ref.storageKey), 'super-secret-key-value');
      expect(ref.toString().contains('super-secret-key-value'), isFalse);

      final entries = await auditRepository.findByTargetEntityId(ref.id);
      expect(entries.single.type, IntegrationAuditEventType.credentialStored);
      expect(
        entries.single.description.contains('super-secret-key-value'),
        isFalse,
      );
    });

    test(
        're-storing for the same organization/provider/kind overwrites '
        'the value and bumps revision, never creates a second ref', () async {
      final storage = FakeIntegrationCredentialStorage();
      final refRepository = InMemoryIntegrationCredentialRefRepository();
      final useCase = StoreIntegrationCredential(
        authorizationPolicy: const AllowAllIntegrationPolicy(),
        storage: storage,
        idGenerator: SequentialIntegrationCredentialRefIdGenerator(),
        repository: refRepository,
        auditRepository: InMemoryIntegrationAuditEntryRepository(),
      );

      final first = await useCase(
        organizationId: 'org-1',
        providerId: 'iyzico',
        kind: IntegrationCredentialKind.apiKey,
        value: 'old-value',
        performedByStaffId: 'owner-1',
        performedAt: DateTime(2026, 1, 1),
      );
      final second = await useCase(
        organizationId: 'org-1',
        providerId: 'iyzico',
        kind: IntegrationCredentialKind.apiKey,
        value: 'new-value',
        performedByStaffId: 'owner-1',
        performedAt: DateTime(2026, 1, 2),
      );

      expect(second.id, first.id);
      expect(second.revision, 2);
      expect(await storage.readValue(second.storageKey), 'new-value');
    });

    test('an unauthorized actor is denied', () async {
      final useCase = StoreIntegrationCredential(
        authorizationPolicy: const DenyAllIntegrationPolicy(),
        storage: FakeIntegrationCredentialStorage(),
        idGenerator: SequentialIntegrationCredentialRefIdGenerator(),
        repository: InMemoryIntegrationCredentialRefRepository(),
        auditRepository: InMemoryIntegrationAuditEntryRepository(),
      );

      expect(
        () => useCase(
          organizationId: 'org-1',
          providerId: 'iyzico',
          kind: IntegrationCredentialKind.apiKey,
          value: 'secret',
          performedByStaffId: 'manager-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
    });
  });

  group('RevokeIntegrationCredential', () {
    test('deletes the value from storage and marks the ref revoked', () async {
      final storage = FakeIntegrationCredentialStorage();
      final refRepository = InMemoryIntegrationCredentialRefRepository();
      final auditRepository = InMemoryIntegrationAuditEntryRepository();
      final stored = await StoreIntegrationCredential(
        authorizationPolicy: const AllowAllIntegrationPolicy(),
        storage: storage,
        idGenerator: SequentialIntegrationCredentialRefIdGenerator(),
        repository: refRepository,
        auditRepository: auditRepository,
      )(
        organizationId: 'org-1',
        providerId: 'iyzico',
        kind: IntegrationCredentialKind.apiKey,
        value: 'secret',
        performedByStaffId: 'owner-1',
        performedAt: DateTime(2026, 1, 1),
      );

      final revoked = await RevokeIntegrationCredential(
        authorizationPolicy: const AllowAllIntegrationPolicy(),
        storage: storage,
        repository: refRepository,
        auditRepository: auditRepository,
      )(
        organizationId: 'org-1',
        providerId: 'iyzico',
        kind: IntegrationCredentialKind.apiKey,
        performedByStaffId: 'owner-1',
        performedAt: DateTime(2026, 1, 2),
      );

      expect(revoked.revoked, isTrue);
      expect(revoked.id, stored.id);
      expect(await storage.readValue(stored.storageKey), isNull);

      final entries = await auditRepository.findByTargetEntityId(revoked.id);
      expect(entries.last.type, IntegrationAuditEventType.credentialRevoked);
    });

    test('throws for a credential that was never stored', () async {
      final useCase = RevokeIntegrationCredential(
        authorizationPolicy: const AllowAllIntegrationPolicy(),
        storage: FakeIntegrationCredentialStorage(),
        repository: InMemoryIntegrationCredentialRefRepository(),
        auditRepository: InMemoryIntegrationAuditEntryRepository(),
      );

      expect(
        () => useCase(
          organizationId: 'org-1',
          providerId: 'iyzico',
          kind: IntegrationCredentialKind.apiKey,
          performedByStaffId: 'owner-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<UnknownIntegrationCredentialViolation>()),
      );
    });

    test('an unauthorized actor is denied', () async {
      final useCase = RevokeIntegrationCredential(
        authorizationPolicy: const DenyAllIntegrationPolicy(),
        storage: FakeIntegrationCredentialStorage(),
        repository: InMemoryIntegrationCredentialRefRepository(),
        auditRepository: InMemoryIntegrationAuditEntryRepository(),
      );

      expect(
        () => useCase(
          organizationId: 'org-1',
          providerId: 'iyzico',
          kind: IntegrationCredentialKind.apiKey,
          performedByStaffId: 'manager-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
    });
  });
}
