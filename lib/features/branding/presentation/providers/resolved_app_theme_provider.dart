import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../admin/presentation/providers/admin_dependencies_provider.dart';
import '../../domain/resolve_effective_brand_theme.dart';
import '../build_theme_from_brand_presentation.dart';
import 'branding_dependencies_provider.dart';

/// The `ThemeData` the running app should actually render — Phase 8
/// (`docs/decisions.md` ADR-025). Resolves [currentOrganizationIdProvider]'s
/// tenant's `TenantBrandTheme` (its **base** identity — "Application
/// Identity → Logo → Colors → Typography," not a per-`BrandChannel`
/// override; a channel override only matters to that channel's own
/// surface, never to the app's own default chrome) and layers its
/// color palette over `AppTheme.lightTheme` via
/// [buildThemeFromBrandPresentation].
///
/// Falls back to `AppTheme.lightTheme` unchanged whenever no brand
/// theme exists for the tenant yet (true today — nothing seeds one for
/// `'org-1'`) — this app's actual current visual appearance is
/// unaffected by this provider existing; it only takes effect once a
/// tenant owner actually sets a brand theme via `SetTenantBrandTheme`.
final resolvedAppThemeProvider = FutureProvider<ThemeData>((ref) async {
  final organizationId = ref.watch(currentOrganizationIdProvider);
  final theme = await ref
      .watch(tenantBrandThemeRepositoryProvider)
      .findByOrganizationId(organizationId);
  if (theme == null) return AppTheme.lightTheme;

  final presentation = EffectiveBrandPresentation(
    colorPalette: theme.colorPalette,
    assets: theme.assets,
  );
  return buildThemeFromBrandPresentation(
    base: AppTheme.lightTheme,
    presentation: presentation,
  );
});
