import 'package:abakus_one_v2/features/payment/data/delivery_payment_policy_repository.dart';
import 'package:abakus_one_v2/features/payment/domain/models/delivery_payment_policy.dart';
import 'package:abakus_one_v2/features/payment/domain/models/payment_method.dart';
import 'package:abakus_one_v2/features/payment/domain/models/payment_method_reporting_category.dart';
import 'package:abakus_one_v2/features/payment/domain/models/payment_method_seed_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InMemoryDeliveryPaymentPolicyRepository seed (Faz P.1 req 12-16)', () {
    test('seeds exactly the 7 LOCKED COD method ids (req 12)', () async {
      final repository = InMemoryDeliveryPaymentPolicyRepository();
      final policy = await repository.current();

      expect(
        policy.enabledMethodIds,
        {
          'cash',
          'credit_card',
          'pluxee',
          'multinet',
          'setcard',
          'edenred',
          'metropol_card',
        },
      );
      expect(policy.enabledMethodIds, hasLength(7));
    });

    test(
        'every seeded id matches a real PaymentMethodSeedData entry '
        '(req 12)', () async {
      final repository = InMemoryDeliveryPaymentPolicyRepository();
      final policy = await repository.current();
      final catalogIds = PaymentMethodSeedData.all.map((m) => m.id).toSet();

      for (final id in policy.enabledMethodIds) {
        expect(catalogIds.contains(id), isTrue, reason: id);
      }
    });

    test('bank_transfer is excluded (req 14)', () async {
      final repository = InMemoryDeliveryPaymentPolicyRepository();
      final policy = await repository.current();
      expect(policy.isEnabledForDeliveryCheckout('bank_transfer'), isFalse);
    });

    test('gift_voucher is excluded (req 15)', () async {
      final repository = InMemoryDeliveryPaymentPolicyRepository();
      final policy = await repository.current();
      expect(policy.isEnabledForDeliveryCheckout('gift_voucher'), isFalse);
    });

    test(
        'an online-payment-style method id (never in the catalog or the '
        'enabled set) is rejected by default-deny semantics — the legacy '
        '"Online Kredi/Banka Kartı" concept has no path into this policy '
        '(req 13)', () async {
      final repository = InMemoryDeliveryPaymentPolicyRepository();
      final policy = await repository.current();
      expect(
        policy.isEnabledForDeliveryCheckout('online_credit_card'),
        isFalse,
      );
    });

    test(
        'an arbitrary unseeded/disabled method id cannot pass the server '
        'policy (req 16)', () async {
      final repository = InMemoryDeliveryPaymentPolicyRepository();
      final policy = await repository.current();
      expect(
          policy.isEnabledForDeliveryCheckout('some_future_method'), isFalse);
    });

    test(
        'setEnabledForDeliveryCheckout can enable a method one at a time, '
        'future-ready without a code change', () async {
      final repository = InMemoryDeliveryPaymentPolicyRepository();
      expect(
        (await repository.current())
            .isEnabledForDeliveryCheckout('bank_transfer'),
        isFalse,
      );

      await repository.setEnabledForDeliveryCheckout('bank_transfer', true);
      expect(
        (await repository.current())
            .isEnabledForDeliveryCheckout('bank_transfer'),
        isTrue,
      );

      await repository.setEnabledForDeliveryCheckout('bank_transfer', false);
      expect(
        (await repository.current())
            .isEnabledForDeliveryCheckout('bank_transfer'),
        isFalse,
      );
    });
  });

  group(
      'DeliveryPaymentPolicy.isAvailableForDeliveryCheckout — isActive is '
      'independent of delivery enablement', () {
    test(
        'an enabled-for-delivery method that is also isActive=true is '
        'available', () {
      const policy = DeliveryPaymentPolicy(enabledMethodIds: {'cash'});
      expect(
        policy.isAvailableForDeliveryCheckout(PaymentMethodSeedData.cash),
        isTrue,
      );
    });

    test(
        'an enabled-for-delivery method that is isActive=false is not '
        'available — PaymentMethod.isActive != enabledForDeliveryCheckout', () {
      const policy = DeliveryPaymentPolicy(enabledMethodIds: {'cash'});
      const inactiveCash = PaymentMethod(
        id: 'cash',
        name: 'Nakit',
        iconAssetPath: 'assets/images/payment/cash.png',
        brandColorValue: 0xFF2E7D32,
        isActive: false,
        supportsSplitPayment: true,
        supportsRefund: true,
        requiresReferenceNumber: false,
        requiresApproval: false,
        sortOrder: 0,
        reportingCategory: PaymentMethodReportingCategory.cash,
      );
      expect(
        policy.isAvailableForDeliveryCheckout(inactiveCash),
        isFalse,
      );
    });

    test(
        'an isActive method that is not enabled for delivery is not '
        'available', () {
      const policy = DeliveryPaymentPolicy(enabledMethodIds: {});
      expect(
        policy.isAvailableForDeliveryCheckout(PaymentMethodSeedData.cash),
        isFalse,
      );
    });
  });

  group(
      'DeliveryPaymentPolicy — no PaymentProviderAdapter invocation '
      '(req 17)', () {
    test(
        'isEnabledForDeliveryCheckout/isAvailableForDeliveryCheckout are '
        'synchronous, pure functions — structurally incapable of awaiting '
        'a provider network call', () {
      const policy = DeliveryPaymentPolicy(enabledMethodIds: {'pluxee'});
      // Pluxee has a real PaymentProviderId in the catalog — proving even
      // a provider-backed method resolves through a plain, synchronous
      // bool, never anything that could invoke an adapter.
      expect(
        policy.isAvailableForDeliveryCheckout(PaymentMethodSeedData.pluxee),
        isA<bool>(),
      );
    });
  });
}
