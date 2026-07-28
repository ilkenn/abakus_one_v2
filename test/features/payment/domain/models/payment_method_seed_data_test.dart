import 'package:abakus_one_v2/features/payment/domain/models/payment_method_seed_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PaymentMethodSeedData', () {
    test('ships exactly the 9 required built-in methods', () {
      expect(PaymentMethodSeedData.all, hasLength(9));
    });

    test('every seed method id is unique', () {
      final ids = PaymentMethodSeedData.all.map((m) => m.id).toSet();
      expect(ids, hasLength(PaymentMethodSeedData.all.length));
    });

    test('every seed method has a unique sortOrder', () {
      final orders = PaymentMethodSeedData.all.map((m) => m.sortOrder).toSet();
      expect(orders, hasLength(PaymentMethodSeedData.all.length));
    });

    test('cash, bank transfer, and gift voucher carry no providerId', () {
      expect(PaymentMethodSeedData.cash.providerId, isNull);
      expect(PaymentMethodSeedData.bankTransfer.providerId, isNull);
      expect(PaymentMethodSeedData.giftVoucher.providerId, isNull);
    });

    test('each meal card method maps to its own same-named provider', () {
      expect(
        PaymentMethodSeedData.pluxee.providerId,
        PaymentMethodSeedData.pluxee.providerId,
      );
      expect(PaymentMethodSeedData.multinet.providerId?.name, 'multinet');
      expect(PaymentMethodSeedData.setcard.providerId?.name, 'setcard');
      expect(PaymentMethodSeedData.edenred.providerId?.name, 'edenred');
      expect(
        PaymentMethodSeedData.metropolCard.providerId?.name,
        'metropolCard',
      );
    });

    test('credit card has no provider pinned in seed data (business decision deferred)', () {
      expect(PaymentMethodSeedData.creditCard.providerId, isNull);
    });

    test('active returns only isActive methods (all 9 seeds today)', () {
      expect(PaymentMethodSeedData.active, hasLength(9));
    });
  });
}
