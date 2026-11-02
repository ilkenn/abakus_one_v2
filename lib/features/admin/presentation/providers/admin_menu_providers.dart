import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/menu_catalog_admin_gateway.dart';
import 'admin_dependencies_provider.dart';

/// Admin Menü — 2026-10-28. One-shot fetches (no live stream — the
/// backend here is callable-only, not a Firestore `.snapshots()` listener,
/// matching `admin_financial_list_providers.dart`'s own exact reasoning
/// for the same shape). Re-fetches on every `ref.watch`/`ref.invalidate`.
final adminMenuCategoriesProvider =
    FutureProvider<List<AdminMenuCategory>>((ref) {
  final gateway = ref.watch(menuCatalogAdminGatewayProvider);
  final organizationId = ref.watch(currentOrganizationIdProvider);
  return gateway.listCategories(organizationId: organizationId);
});

final adminMenuProductsProvider = FutureProvider<List<AdminMenuProduct>>((ref) {
  final gateway = ref.watch(menuCatalogAdminGatewayProvider);
  final organizationId = ref.watch(currentOrganizationIdProvider);
  return gateway.listProducts(organizationId: organizationId);
});
