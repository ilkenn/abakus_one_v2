import 'package:abakus_one_v2/features/orders/domain/models/order_benefit_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('orderBenefitTypeFromWire', () {
    test('"boncukRedemption" parses to OrderBenefitType.boncukRedemption', () {
      expect(orderBenefitTypeFromWire('boncukRedemption'),
          OrderBenefitType.boncukRedemption);
    });

    test('"none" parses to OrderBenefitType.none', () {
      expect(orderBenefitTypeFromWire('none'), OrderBenefitType.none);
    });

    test('null (every pre-P4-E-B order) resolves to OrderBenefitType.none', () {
      expect(orderBenefitTypeFromWire(null), OrderBenefitType.none);
    });

    test(
        'a genuinely unknown/future value degrades to none rather than '
        'throwing — forward compatibility, never a fake benefit', () {
      expect(orderBenefitTypeFromWire('someFutureCampaignBenefit'),
          OrderBenefitType.none);
    });
  });

  group('orderBenefitTypeToWire', () {
    test('round-trips both values through fromWire/toWire', () {
      for (final value in OrderBenefitType.values) {
        expect(orderBenefitTypeFromWire(orderBenefitTypeToWire(value)), value);
      }
    });
  });
}
