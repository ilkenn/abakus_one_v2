import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/payment_hub/application/identity/payment_merchant_account_id_generator.dart';
import 'package:abakus_one_v2/features/payment_hub/application/identity/payment_merchant_method_mapping_id_generator.dart';
import 'package:abakus_one_v2/features/payment_hub/application/identity/payment_settlement_record_id_generator.dart';
import 'package:abakus_one_v2/features/payment_hub/application/use_cases/create_merchant_account.dart';
import 'package:abakus_one_v2/features/payment_hub/application/use_cases/map_payment_method_to_merchant_account.dart';
import 'package:abakus_one_v2/features/payment_hub/application/use_cases/record_payment_settlement.dart';
import 'package:abakus_one_v2/features/payment_hub/data/payment_hub_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/payment_hub/data/payment_merchant_account_repository.dart';
import 'package:abakus_one_v2/features/payment_hub/data/payment_merchant_method_mapping_repository.dart';
import 'package:abakus_one_v2/features/payment_hub/data/payment_settlement_record_repository.dart';
import 'package:abakus_one_v2/features/payment_hub/domain/audit/payment_hub_audit_event_type.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/payment_hub_test_fixtures.dart';

void main() {
  group('Payment Hub full chain', () {
    test(
        'merchant account -> method mapping -> settlement, each step real '
        'and queryable', () async {
      final tenantIntegrationRepository = await seedEnabledIyzicoConfig();
      final accountRepository = InMemoryPaymentMerchantAccountRepository();
      final methodMappingRepository =
          InMemoryPaymentMerchantMethodMappingRepository();
      final settlementRepository = InMemoryPaymentSettlementRecordRepository();
      final auditRepository = InMemoryPaymentHubAuditEntryRepository();

      final account = await CreateMerchantAccount(
        authorizationPolicy: const AllowAllPaymentHubPolicy(),
        providerRegistry: buildTestProviderRegistry(),
        tenantIntegrationRepository: tenantIntegrationRepository,
        idGenerator: SequentialPaymentMerchantAccountIdGenerator(),
        repository: accountRepository,
        auditRepository: auditRepository,
      )(
        organizationId: 'org-1',
        branchId: 'branch-1',
        providerId: 'iyzico',
        accountLabel: 'iyzico - Ana Şube',
        performedByStaffId: 'owner-1',
        performedAt: DateTime(2026, 1, 1),
      );
      expect(account.branchId, 'branch-1');

      final mapping = await MapPaymentMethodToMerchantAccount(
        authorizationPolicy: const AllowAllPaymentHubPolicy(),
        accountRepository: accountRepository,
        idGenerator: SequentialPaymentMerchantMethodMappingIdGenerator(),
        repository: methodMappingRepository,
        auditRepository: auditRepository,
      )(
        merchantAccountId: account.id,
        paymentMethodId: 'card',
        performedByStaffId: 'owner-1',
        performedAt: DateTime(2026, 1, 1),
      );
      expect(mapping.paymentMethodId, 'card');

      final settlement = await RecordPaymentSettlement(
        idGenerator: SequentialPaymentSettlementRecordIdGenerator(),
        repository: settlementRepository,
        auditRepository: auditRepository,
      )(
        organizationId: 'org-1',
        merchantAccountId: account.id,
        externalSettlementId: 'ext-settlement-1',
        amount: Money.fromWhole(1500, Currency.tryLira),
        settledAt: DateTime(2026, 1, 5),
      );
      expect(settlement.amount.minorUnits, 150000);

      final entries = await auditRepository.findByTargetEntityId(account.id);
      expect(
        entries.single.type,
        PaymentHubAuditEventType.merchantAccountCreated,
      );
    });

    test('RecordPaymentSettlement is idempotent by externalSettlementId',
        () async {
      final repository = InMemoryPaymentSettlementRecordRepository();
      final auditRepository = InMemoryPaymentHubAuditEntryRepository();
      final useCase = RecordPaymentSettlement(
        idGenerator: SequentialPaymentSettlementRecordIdGenerator(),
        repository: repository,
        auditRepository: auditRepository,
      );

      final first = await useCase(
        organizationId: 'org-1',
        merchantAccountId: 'merchant-1',
        externalSettlementId: 'ext-settlement-1',
        amount: Money.fromWhole(100, Currency.tryLira),
        settledAt: DateTime(2026, 1, 1),
      );
      final second = await useCase(
        organizationId: 'org-1',
        merchantAccountId: 'merchant-1',
        externalSettlementId: 'ext-settlement-1',
        amount: Money.fromWhole(999, Currency.tryLira),
        settledAt: DateTime(2026, 1, 2),
      );

      expect(second.id, first.id);
      expect(second.amount.minorUnits, first.amount.minorUnits);
      final entries = await auditRepository.findByTargetEntityId(first.id);
      expect(entries, hasLength(1));
    });

    test(
        'CreateMerchantAccount throws when the provider is not enabled '
        'for the tenant', () async {
      final useCase = CreateMerchantAccount(
        authorizationPolicy: const AllowAllPaymentHubPolicy(),
        providerRegistry: buildTestProviderRegistry(),
        tenantIntegrationRepository: await seedEnabledIyzicoConfig(),
        idGenerator: SequentialPaymentMerchantAccountIdGenerator(),
        repository: InMemoryPaymentMerchantAccountRepository(),
        auditRepository: InMemoryPaymentHubAuditEntryRepository(),
      );

      expect(
        () => useCase(
          organizationId: 'org-2',
          branchId: 'branch-1',
          providerId: 'iyzico',
          accountLabel: 'Test',
          performedByStaffId: 'owner-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<IntegrationProviderNotEnabledViolation>()),
      );
    });

    test(
        'CreateMerchantAccount throws for a marketplace-category '
        'providerId', () async {
      final useCase = CreateMerchantAccount(
        authorizationPolicy: const AllowAllPaymentHubPolicy(),
        providerRegistry: buildTestProviderRegistry(),
        tenantIntegrationRepository: await seedEnabledIyzicoConfig(),
        idGenerator: SequentialPaymentMerchantAccountIdGenerator(),
        repository: InMemoryPaymentMerchantAccountRepository(),
        auditRepository: InMemoryPaymentHubAuditEntryRepository(),
      );

      expect(
        () => useCase(
          organizationId: 'org-1',
          branchId: 'branch-1',
          providerId: 'yemeksepeti',
          accountLabel: 'Test',
          performedByStaffId: 'owner-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<UnknownIntegrationProviderViolation>()),
      );
    });

    test('an unauthorized actor cannot create a merchant account', () async {
      final useCase = CreateMerchantAccount(
        authorizationPolicy: const DenyAllPaymentHubPolicy(),
        providerRegistry: buildTestProviderRegistry(),
        tenantIntegrationRepository: await seedEnabledIyzicoConfig(),
        idGenerator: SequentialPaymentMerchantAccountIdGenerator(),
        repository: InMemoryPaymentMerchantAccountRepository(),
        auditRepository: InMemoryPaymentHubAuditEntryRepository(),
      );

      expect(
        () => useCase(
          organizationId: 'org-1',
          branchId: 'branch-1',
          providerId: 'iyzico',
          accountLabel: 'Test',
          performedByStaffId: 'manager-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
    });

    test('MapPaymentMethodToMerchantAccount throws for an unknown account',
        () async {
      final useCase = MapPaymentMethodToMerchantAccount(
        authorizationPolicy: const AllowAllPaymentHubPolicy(),
        accountRepository: InMemoryPaymentMerchantAccountRepository(),
        idGenerator: SequentialPaymentMerchantMethodMappingIdGenerator(),
        repository: InMemoryPaymentMerchantMethodMappingRepository(),
        auditRepository: InMemoryPaymentHubAuditEntryRepository(),
      );

      expect(
        () => useCase(
          merchantAccountId: 'missing',
          paymentMethodId: 'card',
          performedByStaffId: 'owner-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<UnknownPaymentHubEntityViolation>()),
      );
    });
  });
}
