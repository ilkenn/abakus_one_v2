import 'package:abakus_one_v2/features/payment/domain/models/payment_enums.dart';
import 'package:abakus_one_v2/features/payment/domain/models/payment_method_seed_data.dart';
import 'package:abakus_one_v2/features/payment/domain/models/payment_method_snapshot.dart';
import 'package:abakus_one_v2/features/payment/domain/models/payment_request.dart';
import 'package:abakus_one_v2/features/payment/presentation/services/payment_service.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PaymentService.executePayment', () {
    test('routes a card-mapped provider method to its adapter (not configured today)', () async {
      final service = PaymentService();
      final request = PaymentRequest(
        orderId: 'order-1',
        amount: Money.fromWhole(100, Currency.tryLira),
        method: PaymentMethodSnapshot.capture(PaymentMethodSeedData.pluxee),
      );

      final result = await service.executePayment(request);

      expect(result.status, PaymentStatus.notConfigured);
    });

    test('fails cleanly for a manual method with no providerId, never invents one', () async {
      final service = PaymentService();
      final request = PaymentRequest(
        orderId: 'order-1',
        amount: Money.fromWhole(100, Currency.tryLira),
        method: PaymentMethodSnapshot.capture(PaymentMethodSeedData.cash),
      );

      final result = await service.executePayment(request);

      expect(result.status, PaymentStatus.failed);
      expect(result.errorMessage, contains('manuel'));
    });

    test('routes every meal-card method to its own same-named provider adapter', () async {
      final service = PaymentService();
      for (final method in [
        PaymentMethodSeedData.pluxee,
        PaymentMethodSeedData.multinet,
        PaymentMethodSeedData.setcard,
        PaymentMethodSeedData.edenred,
        PaymentMethodSeedData.metropolCard,
      ]) {
        final result = await service.executePayment(
          PaymentRequest(
            orderId: 'order-1',
            amount: Money.fromWhole(50, Currency.tryLira),
            method: PaymentMethodSnapshot.capture(method),
          ),
        );
        expect(result.status, PaymentStatus.notConfigured, reason: method.id);
      }
    });
  });

  group('PaymentService.executeRefund', () {
    test('routes to the matching provider adapter (not configured today)', () async {
      final service = PaymentService();

      final result = await service.executeRefund(
        method: PaymentMethodSnapshot.capture(PaymentMethodSeedData.pluxee),
        transactionId: 'txn-1',
        amount: Money.fromWhole(50, Currency.tryLira),
      );

      expect(result.status, PaymentStatus.notConfigured);
    });

    test('fails cleanly for a manual method with no providerId', () async {
      final service = PaymentService();

      final result = await service.executeRefund(
        method: PaymentMethodSnapshot.capture(PaymentMethodSeedData.cash),
        transactionId: 'txn-1',
        amount: Money.fromWhole(50, Currency.tryLira),
      );

      expect(result.status, PaymentStatus.failed);
      expect(result.errorMessage, contains('manuel'));
    });
  });
}
