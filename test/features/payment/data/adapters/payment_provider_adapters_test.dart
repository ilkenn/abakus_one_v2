import 'package:abakus_one_v2/features/payment/data/adapters/adyen_adapter.dart';
import 'package:abakus_one_v2/features/payment/data/adapters/edenred_adapter.dart';
import 'package:abakus_one_v2/features/payment/data/adapters/iyzico_adapter.dart';
import 'package:abakus_one_v2/features/payment/data/adapters/metropol_card_adapter.dart';
import 'package:abakus_one_v2/features/payment/data/adapters/multinet_adapter.dart';
import 'package:abakus_one_v2/features/payment/data/adapters/ode_al_adapter.dart';
import 'package:abakus_one_v2/features/payment/data/adapters/pax_teb_adapter.dart';
import 'package:abakus_one_v2/features/payment/data/adapters/payment_provider_adapter.dart';
import 'package:abakus_one_v2/features/payment/data/adapters/pluxee_adapter.dart';
import 'package:abakus_one_v2/features/payment/data/adapters/setcard_adapter.dart';
import 'package:abakus_one_v2/features/payment/data/adapters/stripe_adapter.dart';
import 'package:abakus_one_v2/features/payment/domain/models/payment_enums.dart';
import 'package:abakus_one_v2/features/payment/domain/models/payment_method_seed_data.dart';
import 'package:abakus_one_v2/features/payment/domain/models/payment_method_snapshot.dart';
import 'package:abakus_one_v2/features/payment/domain/models/payment_request.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final adapters = <String, PaymentProviderAdapter>{
    'iyzico': IyzicoPaymentAdapter(),
    'stripe': StripePaymentAdapter(),
    'adyen': AdyenPaymentAdapter(),
    'odeal': OdeAlPaymentAdapter(),
    'pluxee': PluxeePaymentAdapter(),
    'multinet': MultinetPaymentAdapter(),
    'setcard': SetcardPaymentAdapter(),
    'edenred': EdenredPaymentAdapter(),
    'metropolCard': MetropolCardPaymentAdapter(),
    'paxTeb': PaxTebTerminalAdapter(),
  };

  group('Every PaymentProviderAdapter — Money-based, not configured', () {
    for (final entry in adapters.entries) {
      test('${entry.key}: processPayment returns notConfigured', () async {
        final result = await entry.value.processPayment(
          PaymentRequest(
            orderId: 'order-1',
            amount: Money.fromWhole(100, Currency.tryLira),
            method:
                PaymentMethodSnapshot.capture(PaymentMethodSeedData.creditCard),
          ),
        );
        expect(result.status, PaymentStatus.notConfigured);
      });

      test(
          '${entry.key}: refundPayment accepts Money and returns notConfigured',
          () async {
        final result = await entry.value.refundPayment(
          'txn-1',
          Money.fromWhole(50, Currency.tryLira),
        );
        expect(result.status, PaymentStatus.notConfigured);
      });
    }
  });
}
