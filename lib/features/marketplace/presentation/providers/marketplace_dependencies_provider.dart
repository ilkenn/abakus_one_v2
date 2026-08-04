import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/identity/marketplace_account_id_generator.dart';
import '../../application/identity/marketplace_branch_mapping_id_generator.dart';
import '../../application/identity/marketplace_menu_mapping_id_generator.dart';
import '../../application/identity/marketplace_order_mapping_id_generator.dart';
import '../../application/identity/marketplace_store_id_generator.dart';
import '../../application/identity/virtual_restaurant_id_generator.dart';
import '../../data/marketplace_account_repository.dart';
import '../../data/marketplace_audit_entry_repository.dart';
import '../../data/marketplace_branch_mapping_repository.dart';
import '../../data/marketplace_menu_mapping_repository.dart';
import '../../data/marketplace_order_mapping_repository.dart';
import '../../data/marketplace_store_repository.dart';
import '../../data/virtual_restaurant_repository.dart';

/// Central Riverpod wiring for `features/marketplace` — Phase 8
/// (`docs/decisions.md` ADR-025). Repository/id-generator providers
/// only, matching every other Phase 7/8 dependencies-provider file's
/// convention.
final marketplaceAccountRepositoryProvider =
    Provider<MarketplaceAccountRepository>((ref) {
  return InMemoryMarketplaceAccountRepository();
});

final marketplaceAccountIdGeneratorProvider =
    Provider<MarketplaceAccountIdGenerator>((ref) {
  return SequentialMarketplaceAccountIdGenerator();
});

final marketplaceStoreRepositoryProvider =
    Provider<MarketplaceStoreRepository>((ref) {
  return InMemoryMarketplaceStoreRepository();
});

final marketplaceStoreIdGeneratorProvider =
    Provider<MarketplaceStoreIdGenerator>((ref) {
  return SequentialMarketplaceStoreIdGenerator();
});

final virtualRestaurantRepositoryProvider =
    Provider<VirtualRestaurantRepository>((ref) {
  return InMemoryVirtualRestaurantRepository();
});

final virtualRestaurantIdGeneratorProvider =
    Provider<VirtualRestaurantIdGenerator>((ref) {
  return SequentialVirtualRestaurantIdGenerator();
});

final marketplaceBranchMappingRepositoryProvider =
    Provider<MarketplaceBranchMappingRepository>((ref) {
  return InMemoryMarketplaceBranchMappingRepository();
});

final marketplaceBranchMappingIdGeneratorProvider =
    Provider<MarketplaceBranchMappingIdGenerator>((ref) {
  return SequentialMarketplaceBranchMappingIdGenerator();
});

final marketplaceMenuMappingRepositoryProvider =
    Provider<MarketplaceMenuMappingRepository>((ref) {
  return InMemoryMarketplaceMenuMappingRepository();
});

final marketplaceMenuMappingIdGeneratorProvider =
    Provider<MarketplaceMenuMappingIdGenerator>((ref) {
  return SequentialMarketplaceMenuMappingIdGenerator();
});

final marketplaceOrderMappingRepositoryProvider =
    Provider<MarketplaceOrderMappingRepository>((ref) {
  return InMemoryMarketplaceOrderMappingRepository();
});

final marketplaceOrderMappingIdGeneratorProvider =
    Provider<MarketplaceOrderMappingIdGenerator>((ref) {
  return SequentialMarketplaceOrderMappingIdGenerator();
});

final marketplaceAuditEntryRepositoryProvider =
    Provider<MarketplaceAuditEntryRepository>((ref) {
  return InMemoryMarketplaceAuditEntryRepository();
});
