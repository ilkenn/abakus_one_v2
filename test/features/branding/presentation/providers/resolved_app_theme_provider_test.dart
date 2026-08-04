import 'package:abakus_one_v2/core/theme/app_theme.dart';
import 'package:abakus_one_v2/features/admin/presentation/providers/admin_dependencies_provider.dart';
import 'package:abakus_one_v2/features/branding/domain/brand_color_palette.dart';
import 'package:abakus_one_v2/features/branding/domain/brand_typography.dart';
import 'package:abakus_one_v2/features/branding/domain/tenant_brand_theme.dart';
import 'package:abakus_one_v2/features/branding/presentation/providers/branding_dependencies_provider.dart';
import 'package:abakus_one_v2/features/branding/presentation/providers/resolved_app_theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolvedAppThemeProvider', () {
    test('falls back to AppTheme.lightTheme when no brand theme exists',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final theme = await container.read(resolvedAppThemeProvider.future);

      expect(
          theme.colorScheme.primary, AppTheme.lightTheme.colorScheme.primary);
    });

    test(
        'applies the tenant brand theme once one is set for the current '
        'organization', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final organizationId = container.read(currentOrganizationIdProvider);
      await container.read(tenantBrandThemeRepositoryProvider).save(
            TenantBrandTheme(
              id: 'theme-1',
              organizationId: organizationId,
              brandDisplayName: 'Test Brand',
              colorPalette: const BrandColorPalette(
                primaryColorHex: '#FF0000',
                secondaryColorHex: '#00FF00',
                accentColorHex: '#0000FF',
              ),
              typography: const BrandTypography(fontFamilyName: 'Inter'),
              createdAt: DateTime(2026, 1, 1),
              revision: 1,
            ),
          );
      container.invalidate(resolvedAppThemeProvider);

      final theme = await container.read(resolvedAppThemeProvider.future);

      expect(theme.colorScheme.primary, const Color.fromARGB(255, 255, 0, 0));
    });
  });
}
