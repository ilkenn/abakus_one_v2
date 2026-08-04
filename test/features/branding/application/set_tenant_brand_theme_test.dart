import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/branding/application/identity/tenant_brand_theme_id_generator.dart';
import 'package:abakus_one_v2/features/branding/application/use_cases/set_tenant_brand_theme.dart';
import 'package:abakus_one_v2/features/branding/data/branding_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/branding/data/tenant_brand_theme_repository.dart';
import 'package:abakus_one_v2/features/branding/domain/audit/branding_audit_event_type.dart';
import 'package:abakus_one_v2/features/branding/domain/brand_color_palette.dart';
import 'package:abakus_one_v2/features/branding/domain/brand_typography.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/branding_test_fixtures.dart';

const _validPalette = BrandColorPalette(
  primaryColorHex: '#111111',
  secondaryColorHex: '#222222',
  accentColorHex: '#333333',
);
const _typography = BrandTypography(fontFamilyName: 'Inter');

void main() {
  group('SetTenantBrandTheme', () {
    test('creates a new theme for an organization with none yet', () async {
      final repository = InMemoryTenantBrandThemeRepository();
      final auditRepository = InMemoryBrandingAuditEntryRepository();
      final useCase = SetTenantBrandTheme(
        authorizationPolicy: const AllowAllBrandingPolicy(),
        idGenerator: SequentialTenantBrandThemeIdGenerator(),
        repository: repository,
        auditRepository: auditRepository,
      );

      final theme = await useCase(
        organizationId: 'org-1',
        brandDisplayName: 'Test Brand',
        colorPalette: _validPalette,
        typography: _typography,
        performedByStaffId: 'owner-1',
        performedAt: DateTime(2026, 1, 1),
      );

      expect(theme.organizationId, 'org-1');
      expect(theme.revision, 1);
      expect(await repository.findByOrganizationId('org-1'), isNotNull);

      final entries = await auditRepository.findByTargetEntityId(theme.id);
      expect(entries.single.type, BrandingAuditEventType.tenantBrandThemeSet);
    });

    test('updating an existing theme reuses its id and bumps revision',
        () async {
      final repository = InMemoryTenantBrandThemeRepository();
      final useCase = SetTenantBrandTheme(
        authorizationPolicy: const AllowAllBrandingPolicy(),
        idGenerator: SequentialTenantBrandThemeIdGenerator(),
        repository: repository,
        auditRepository: InMemoryBrandingAuditEntryRepository(),
      );

      final first = await useCase(
        organizationId: 'org-1',
        brandDisplayName: 'Original',
        colorPalette: _validPalette,
        typography: _typography,
        performedByStaffId: 'owner-1',
        performedAt: DateTime(2026, 1, 1),
      );
      final second = await useCase(
        organizationId: 'org-1',
        brandDisplayName: 'Updated',
        colorPalette: _validPalette,
        typography: _typography,
        performedByStaffId: 'owner-1',
        performedAt: DateTime(2026, 1, 2),
      );

      expect(second.id, first.id);
      expect(second.revision, 2);
      expect(second.brandDisplayName, 'Updated');
    });

    test('an invalid color palette throws', () async {
      final useCase = SetTenantBrandTheme(
        authorizationPolicy: const AllowAllBrandingPolicy(),
        idGenerator: SequentialTenantBrandThemeIdGenerator(),
        repository: InMemoryTenantBrandThemeRepository(),
        auditRepository: InMemoryBrandingAuditEntryRepository(),
      );

      expect(
        () => useCase(
          organizationId: 'org-1',
          brandDisplayName: 'Test Brand',
          colorPalette: const BrandColorPalette(
            primaryColorHex: 'not-a-color',
            secondaryColorHex: '#222222',
            accentColorHex: '#333333',
          ),
          typography: _typography,
          performedByStaffId: 'owner-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<InvalidBrandColorPaletteViolation>()),
      );
    });

    test('an unauthorized actor is denied', () async {
      final useCase = SetTenantBrandTheme(
        authorizationPolicy: const DenyAllBrandingPolicy(),
        idGenerator: SequentialTenantBrandThemeIdGenerator(),
        repository: InMemoryTenantBrandThemeRepository(),
        auditRepository: InMemoryBrandingAuditEntryRepository(),
      );

      expect(
        () => useCase(
          organizationId: 'org-1',
          brandDisplayName: 'Test Brand',
          colorPalette: _validPalette,
          typography: _typography,
          performedByStaffId: 'manager-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
    });
  });
}
