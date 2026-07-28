import 'package:abakus_one_v2/features/orders/domain/pricing/price_breakdown.dart';
import 'package:abakus_one_v2/features/orders/domain/pricing/price_calculator.dart';
import 'package:abakus_one_v2/features/orders/domain/receipt/courier_receipt_summary_builder.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('remainingToCollectAmount zero produces the paid label', () {
    final pricing = PriceCalculator.calculate(
      lines: const [],
      currency: Currency.tryLira,
      deliveryFee: Money.fromWhole(25, Currency.tryLira),
    );

    final summary = CourierReceiptSummaryBuilder.build(
      pricing: pricing,
      alreadyPaidAmount: pricing.grandTotal,
      remainingToCollectAmount: Money.zero(Currency.tryLira),
    );

    expect(summary.paymentTypeLabel, 'ÖDENDİ');
    expect(summary.hasRemainingCollection, isFalse);
    expect(summary.deliveryFee, Money.fromWhole(25, Currency.tryLira));
  });

  test(
      'a positive remaining amount produces the collection label (the worked example)',
      () {
    final pricing = PriceBreakdown(
      grossSubtotal: Money.fromWhole(645, Currency.tryLira),
      discount: Money.zero(Currency.tryLira),
      taxableBase: Money.zero(Currency.tryLira),
      vatAmount: Money.zero(Currency.tryLira),
      serviceFee: Money.zero(Currency.tryLira),
      deliveryFee: Money.zero(Currency.tryLira),
      packagingFee: Money.zero(Currency.tryLira),
      tip: Money.zero(Currency.tryLira),
      grandTotal: Money.fromWhole(645, Currency.tryLira),
    );

    final summary = CourierReceiptSummaryBuilder.build(
      pricing: pricing,
      alreadyPaidAmount: Money.zero(Currency.tryLira),
      remainingToCollectAmount: Money.fromWhole(645, Currency.tryLira),
    );

    expect(summary.paymentTypeLabel, 'KAPIDA TAHSİLAT');
    expect(summary.hasRemainingCollection, isTrue);
    expect(summary.remainingToCollectAmount,
        Money.fromWhole(645, Currency.tryLira));
  });
}
