import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/marketplace/application/identity/marketplace_account_id_generator.dart';
import 'package:abakus_one_v2/features/marketplace/application/identity/marketplace_branch_mapping_id_generator.dart';
import 'package:abakus_one_v2/features/marketplace/application/identity/marketplace_menu_mapping_id_generator.dart';
import 'package:abakus_one_v2/features/marketplace/application/identity/marketplace_order_mapping_id_generator.dart';
import 'package:abakus_one_v2/features/marketplace/application/identity/marketplace_store_id_generator.dart';
import 'package:abakus_one_v2/features/marketplace/application/identity/virtual_restaurant_id_generator.dart';
import 'package:abakus_one_v2/features/marketplace/application/use_cases/create_marketplace_account.dart';
import 'package:abakus_one_v2/features/marketplace/application/use_cases/create_marketplace_store.dart';
import 'package:abakus_one_v2/features/marketplace/application/use_cases/create_virtual_restaurant.dart';
import 'package:abakus_one_v2/features/marketplace/application/use_cases/map_menu_product_to_marketplace_listing.dart';
import 'package:abakus_one_v2/features/marketplace/application/use_cases/map_virtual_restaurant_to_branch.dart';
import 'package:abakus_one_v2/features/marketplace/application/use_cases/record_marketplace_order_mapping.dart';
import 'package:abakus_one_v2/features/marketplace/data/marketplace_account_repository.dart';
import 'package:abakus_one_v2/features/marketplace/data/marketplace_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/marketplace/data/marketplace_branch_mapping_repository.dart';
import 'package:abakus_one_v2/features/marketplace/data/marketplace_menu_mapping_repository.dart';
import 'package:abakus_one_v2/features/marketplace/data/marketplace_order_mapping_repository.dart';
import 'package:abakus_one_v2/features/marketplace/data/marketplace_store_repository.dart';
import 'package:abakus_one_v2/features/marketplace/data/virtual_restaurant_repository.dart';
import 'package:abakus_one_v2/features/marketplace/domain/marketplace_order_mapping_status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/marketplace_test_fixtures.dart';

void main() {
  group('Marketplace Hub full chain', () {
    test(
        'account -> store -> virtual restaurant -> branch mapping -> menu '
        'mapping -> order mapping, each step real and queryable', () async {
      final tenantIntegrationRepository = await seedEnabledYemeksepetiConfig();
      final accountRepository = InMemoryMarketplaceAccountRepository();
      final storeRepository = InMemoryMarketplaceStoreRepository();
      final virtualRestaurantRepository = InMemoryVirtualRestaurantRepository();
      final branchMappingRepository =
          InMemoryMarketplaceBranchMappingRepository();
      final menuMappingRepository = InMemoryMarketplaceMenuMappingRepository();
      final orderMappingRepository =
          InMemoryMarketplaceOrderMappingRepository();
      final auditRepository = InMemoryMarketplaceAuditEntryRepository();

      final account = await CreateMarketplaceAccount(
        authorizationPolicy: const AllowAllMarketplacePolicy(),
        providerRegistry: buildTestProviderRegistry(),
        tenantIntegrationRepository: tenantIntegrationRepository,
        idGenerator: SequentialMarketplaceAccountIdGenerator(),
        repository: accountRepository,
        auditRepository: auditRepository,
      )(
        organizationId: 'org-1',
        providerId: 'yemeksepeti',
        accountLabel: 'Yemeksepeti - Kadıköy',
        performedByStaffId: 'owner-1',
        performedAt: DateTime(2026, 1, 1),
      );

      final store = await CreateMarketplaceStore(
        authorizationPolicy: const AllowAllMarketplacePolicy(),
        accountRepository: accountRepository,
        idGenerator: SequentialMarketplaceStoreIdGenerator(),
        repository: storeRepository,
        auditRepository: auditRepository,
      )(
        marketplaceAccountId: account.id,
        externalStoreId: 'ext-store-1',
        storeName: 'Kadıköy Şubesi',
        performedByStaffId: 'owner-1',
        performedAt: DateTime(2026, 1, 1),
      );

      final virtualRestaurant = await CreateVirtualRestaurant(
        authorizationPolicy: const AllowAllMarketplacePolicy(),
        storeRepository: storeRepository,
        accountRepository: accountRepository,
        idGenerator: SequentialVirtualRestaurantIdGenerator(),
        repository: virtualRestaurantRepository,
        auditRepository: auditRepository,
      )(
        marketplaceStoreId: store.id,
        name: 'Abaküs Bowl',
        performedByStaffId: 'owner-1',
        performedAt: DateTime(2026, 1, 1),
      );

      final branchMapping = await MapVirtualRestaurantToBranch(
        authorizationPolicy: const AllowAllMarketplacePolicy(),
        virtualRestaurantRepository: virtualRestaurantRepository,
        storeRepository: storeRepository,
        accountRepository: accountRepository,
        idGenerator: SequentialMarketplaceBranchMappingIdGenerator(),
        repository: branchMappingRepository,
        auditRepository: auditRepository,
      )(
        virtualRestaurantId: virtualRestaurant.id,
        branchId: 'branch-1',
        performedByStaffId: 'owner-1',
        performedAt: DateTime(2026, 1, 1),
      );
      expect(branchMapping.branchId, 'branch-1');

      final menuMapping = await MapMenuProductToMarketplaceListing(
        authorizationPolicy: const AllowAllMarketplacePolicy(),
        virtualRestaurantRepository: virtualRestaurantRepository,
        storeRepository: storeRepository,
        accountRepository: accountRepository,
        idGenerator: SequentialMarketplaceMenuMappingIdGenerator(),
        repository: menuMappingRepository,
        auditRepository: auditRepository,
      )(
        virtualRestaurantId: virtualRestaurant.id,
        internalMenuProductId: 'product-1',
        externalProductId: 'ext-product-1',
        performedByStaffId: 'owner-1',
        performedAt: DateTime(2026, 1, 1),
      );
      expect(menuMapping.externalProductId, 'ext-product-1');

      final orderMapping = await RecordMarketplaceOrderMapping(
        idGenerator: SequentialMarketplaceOrderMappingIdGenerator(),
        repository: orderMappingRepository,
        auditRepository: auditRepository,
      )(
        organizationId: 'org-1',
        virtualRestaurantId: virtualRestaurant.id,
        externalOrderId: 'ext-order-1',
        receivedAt: DateTime(2026, 1, 2),
      );
      expect(orderMapping.status, MarketplaceOrderMappingStatus.received);
      expect(orderMapping.internalOrderId, isNull);
    });

    test('RecordMarketplaceOrderMapping is idempotent by externalOrderId',
        () async {
      final repository = InMemoryMarketplaceOrderMappingRepository();
      final auditRepository = InMemoryMarketplaceAuditEntryRepository();
      final useCase = RecordMarketplaceOrderMapping(
        idGenerator: SequentialMarketplaceOrderMappingIdGenerator(),
        repository: repository,
        auditRepository: auditRepository,
      );

      final first = await useCase(
        organizationId: 'org-1',
        virtualRestaurantId: 'vr-1',
        externalOrderId: 'ext-order-1',
        receivedAt: DateTime(2026, 1, 1),
      );
      final second = await useCase(
        organizationId: 'org-1',
        virtualRestaurantId: 'vr-1',
        externalOrderId: 'ext-order-1',
        receivedAt: DateTime(2026, 1, 2),
      );

      expect(second.id, first.id);
      final entries = await auditRepository.findByTargetEntityId(first.id);
      expect(entries, hasLength(1));
    });

    test(
        'CreateMarketplaceAccount throws when the provider is not enabled '
        'for the tenant', () async {
      final useCase = CreateMarketplaceAccount(
        authorizationPolicy: const AllowAllMarketplacePolicy(),
        providerRegistry: buildTestProviderRegistry(),
        tenantIntegrationRepository: await seedEnabledYemeksepetiConfig(),
        idGenerator: SequentialMarketplaceAccountIdGenerator(),
        repository: InMemoryMarketplaceAccountRepository(),
        auditRepository: InMemoryMarketplaceAuditEntryRepository(),
      );

      expect(
        () => useCase(
          organizationId: 'org-2',
          providerId: 'yemeksepeti',
          accountLabel: 'Test',
          performedByStaffId: 'owner-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<IntegrationProviderNotEnabledViolation>()),
      );
    });

    test(
        'CreateMarketplaceAccount throws for a payment-category '
        'providerId', () async {
      final useCase = CreateMarketplaceAccount(
        authorizationPolicy: const AllowAllMarketplacePolicy(),
        providerRegistry: buildTestProviderRegistry(),
        tenantIntegrationRepository: await seedEnabledYemeksepetiConfig(),
        idGenerator: SequentialMarketplaceAccountIdGenerator(),
        repository: InMemoryMarketplaceAccountRepository(),
        auditRepository: InMemoryMarketplaceAuditEntryRepository(),
      );

      expect(
        () => useCase(
          organizationId: 'org-1',
          providerId: 'iyzico',
          accountLabel: 'Test',
          performedByStaffId: 'owner-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<UnknownIntegrationProviderViolation>()),
      );
    });

    test('an unauthorized actor cannot create a marketplace account', () async {
      final useCase = CreateMarketplaceAccount(
        authorizationPolicy: const DenyAllMarketplacePolicy(),
        providerRegistry: buildTestProviderRegistry(),
        tenantIntegrationRepository: await seedEnabledYemeksepetiConfig(),
        idGenerator: SequentialMarketplaceAccountIdGenerator(),
        repository: InMemoryMarketplaceAccountRepository(),
        auditRepository: InMemoryMarketplaceAuditEntryRepository(),
      );

      expect(
        () => useCase(
          organizationId: 'org-1',
          providerId: 'yemeksepeti',
          accountLabel: 'Test',
          performedByStaffId: 'manager-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
    });

    test('CreateMarketplaceStore throws for an unknown account', () async {
      final useCase = CreateMarketplaceStore(
        authorizationPolicy: const AllowAllMarketplacePolicy(),
        accountRepository: InMemoryMarketplaceAccountRepository(),
        idGenerator: SequentialMarketplaceStoreIdGenerator(),
        repository: InMemoryMarketplaceStoreRepository(),
        auditRepository: InMemoryMarketplaceAuditEntryRepository(),
      );

      expect(
        () => useCase(
          marketplaceAccountId: 'missing',
          externalStoreId: 'ext-1',
          storeName: 'Test',
          performedByStaffId: 'owner-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<UnknownMarketplaceEntityViolation>()),
      );
    });
  });
}
