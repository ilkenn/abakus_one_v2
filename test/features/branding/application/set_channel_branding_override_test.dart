import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/branding/application/use_cases/set_channel_branding_override.dart';
import 'package:abakus_one_v2/features/branding/data/branding_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/branding/data/tenant_brand_theme_repository.dart';
import 'package:abakus_one_v2/features/branding/domain/audit/branding_audit_event_type.dart';
import 'package:abakus_one_v2/features/branding/domain/brand_channel.dart';
import 'package:abakus_one_v2/features/branding/domain/brand_color_palette.dart';
import 'package:abakus_one_v2/features/branding/domain/brand_typography.dart';
import 'package:abakus_one_v2/features/branding/domain/channel_branding_override.dart';
import 'package:abakus_one_v2/features/branding/domain/tenant_brand_theme.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/branding_test_fixtures.dart';

void main() {
  Future<TenantBrandThemeRepository> seededRepository() async {
    final repository = InMemoryTenantBrandThemeRepository();
    await repository.save(TenantBrandTheme(
      id: 'theme-1',
      organizationId: 'org-1',
      brandDisplayName: 'Test Brand',
      colorPalette: const BrandColorPalette(
        primaryColorHex: '#111111',
        secondaryColorHex: '#222222',
        accentColorHex: '#333333',
      ),
      typography: const BrandTypography(fontFamilyName: 'Inter'),
      createdAt: DateTime(2026, 1, 1),
      revision: 1,
    ));
    return repository;
  }

  group('SetChannelBrandingOverride', () {
    test('sets an override for a channel, bumping the theme revision',
        () async {
      final repository = await seededRepository();
      final useCase = SetChannelBrandingOverride(
        authorizationPolicy: const AllowAllBrandingPolicy(),
        repository: repository,
        auditRepository: InMemoryBrandingAuditEntryRepository(),
      );

      final updated = await useCase(
        organizationId: 'org-1',
        channel: BrandChannel.receipt,
        override: const ChannelBrandingOverride(
          colorPalette: BrandColorPalette(
            primaryColorHex: '#AAAAAA',
            secondaryColorHex: '#BBBBBB',
            accentColorHex: '#CCCCCC',
          ),
        ),
        performedByStaffId: 'owner-1',
        performedAt: DateTime(2026, 1, 2),
      );

      expect(updated.revision, 2);
      expect(
          updated.channelOverrides.containsKey(BrandChannel.receipt), isTrue);
    });

    test('throws when no base theme exists for the organization yet', () async {
      final useCase = SetChannelBrandingOverride(
        authorizationPolicy: const AllowAllBrandingPolicy(),
        repository: InMemoryTenantBrandThemeRepository(),
        auditRepository: InMemoryBrandingAuditEntryRepository(),
      );

      expect(
        () => useCase(
          organizationId: 'org-1',
          channel: BrandChannel.receipt,
          override: const ChannelBrandingOverride(),
          performedByStaffId: 'owner-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<UnknownBrandThemeViolation>()),
      );
    });

    test('an unauthorized actor is denied', () async {
      final repository = await seededRepository();
      final useCase = SetChannelBrandingOverride(
        authorizationPolicy: const DenyAllBrandingPolicy(),
        repository: repository,
        auditRepository: InMemoryBrandingAuditEntryRepository(),
      );

      expect(
        () => useCase(
          organizationId: 'org-1',
          channel: BrandChannel.receipt,
          override: const ChannelBrandingOverride(),
          performedByStaffId: 'manager-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
    });

    test('audits the override with the correct event type', () async {
      final repository = await seededRepository();
      final auditRepository = InMemoryBrandingAuditEntryRepository();
      final useCase = SetChannelBrandingOverride(
        authorizationPolicy: const AllowAllBrandingPolicy(),
        repository: repository,
        auditRepository: auditRepository,
      );

      final updated = await useCase(
        organizationId: 'org-1',
        channel: BrandChannel.push,
        override: const ChannelBrandingOverride(),
        performedByStaffId: 'owner-1',
        performedAt: DateTime(2026, 1, 2),
      );

      final entries = await auditRepository.findByTargetEntityId(updated.id);
      expect(
        entries.single.type,
        BrandingAuditEventType.channelBrandingOverrideSet,
      );
    });
  });
}
