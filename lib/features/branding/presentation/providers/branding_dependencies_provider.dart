import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/identity/tenant_brand_theme_id_generator.dart';
import '../../data/branding_audit_entry_repository.dart';
import '../../data/tenant_brand_theme_repository.dart';

/// Central Riverpod wiring for `features/branding` — Phase 8
/// (`docs/decisions.md` ADR-025). Repository/id-generator providers
/// only, matching every other Phase 7/8 dependencies-provider file's
/// convention — screens/use cases construct their own use case inline
/// with an injected `authorizationPolicy`.
final tenantBrandThemeRepositoryProvider =
    Provider<TenantBrandThemeRepository>((ref) {
  return InMemoryTenantBrandThemeRepository();
});

final tenantBrandThemeIdGeneratorProvider =
    Provider<TenantBrandThemeIdGenerator>((ref) {
  return SequentialTenantBrandThemeIdGenerator();
});

final brandingAuditEntryRepositoryProvider =
    Provider<BrandingAuditEntryRepository>((ref) {
  return InMemoryBrandingAuditEntryRepository();
});
