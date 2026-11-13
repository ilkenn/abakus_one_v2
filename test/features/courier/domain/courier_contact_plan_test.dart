import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/features/courier/domain/work/courier_contact_plan.dart';
import 'package:abakus_one_v2/features/courier/domain/work/courier_work_models.dart';

CourierWorkOrder _order({
  CourierWorkOrderStatus status = CourierWorkOrderStatus.departed,
  String? phone = '+90 532 111 22 33',
  CourierOrderSource source = CourierOrderSource.own,
  String? code,
  String? switchboard,
  double? lat,
  double? lng,
  String addressLine = 'Moda Caddesi No: 12',
}) =>
    CourierWorkOrder(
      orderId: 'o1',
      orderNumber: 'DL-1',
      branchName: '',
      customerName: 'Ayşe Demir',
      customerPhone: phone,
      neighborhoodName: 'Caferağa',
      addressLine: addressLine,
      courierNote: '',
      amountDueMinorUnits: 0,
      plannedPaymentMethodId: null,
      reportedPaymentMethodId: null,
      status: status,
      destinationLatitude: lat,
      destinationLongitude: lng,
      source: source,
      marketplaceOrderCode: code,
      switchboardPhone: switchboard,
    );

void main() {
  group('courierCallPlan (ADR-085 stage 4)', () {
    test('own orders and Yemeksepeti call the customer', () {
      expect(courierCallPlan(_order())!.uri.toString(), 'tel:+905321112233');
      final ys = courierCallPlan(_order(
          source: CourierOrderSource.yemeksepeti,
          code: '999',
          switchboard: '02123653403'))!;
      expect(ys.uri.toString(), 'tel:+905321112233');
      expect(ys.label, 'Müşteriyi Ara');
    });

    test('Trendyol/Getir call the switchboard, pause, key the code and #', () {
      final plan = courierCallPlan(_order(
        source: CourierOrderSource.trendyol,
        code: 'TY-123456',
        switchboard: '0212 365 34 03',
      ))!;
      expect(plan.uri.toString(), 'tel:02123653403,,123456%23');
      expect(plan.label, 'Trendyol Santrali Ara');

      final getir = courierCallPlan(_order(
          source: CourierOrderSource.getir,
          code: '42',
          switchboard: '02123653403'))!;
      expect(getir.uri.toString(), 'tel:02123653403,,42%23');
    });

    test('no code: just the switchboard; no switchboard: nothing', () {
      expect(
          courierCallPlan(_order(
                  source: CourierOrderSource.getir,
                  switchboard: '02123653403'))!
              .uri
              .toString(),
          'tel:02123653403');
      expect(
          courierCallPlan(_order(source: CourierOrderSource.trendyol)), isNull);
    });

    test('nothing to call after delivery (KVKK) or without a number', () {
      expect(
          courierCallPlan(_order(
              status: CourierWorkOrderStatus.deliveredAwaitingSettlement)),
          isNull);
      expect(courierCallPlan(_order(phone: null)), isNull);
    });
  });

  group('courierNavigationOptions (ADR-085 stage 4)', () {
    test('uses the pin when the address has one', () {
      final options = courierNavigationOptions(_order(lat: 40.98, lng: 29.03));
      expect(options.map((o) => o.label),
          ['Google Haritalar', 'Apple Haritalar', 'Yandex Haritalar']);
      expect(options[0].uri.queryParameters['destination'], '40.98,29.03');
      expect(options[1].uri.queryParameters['daddr'], '40.98,29.03');
      expect(options[2].uri.queryParameters['rtext'], '~40.98,29.03');
    });

    test('falls back to the written address', () {
      final options = courierNavigationOptions(_order());
      expect(options[0].uri.queryParameters['destination'],
          'Moda Caddesi No: 12, Caferağa');
      expect(options[2].uri.queryParameters['text'],
          'Moda Caddesi No: 12, Caferağa');
    });

    test('nothing after delivery', () {
      expect(
          courierNavigationOptions(_order(
              status: CourierWorkOrderStatus.deliveredAwaitingSettlement,
              lat: 1,
              lng: 2)),
          isEmpty);
    });

    test('parses the projection fields', () {
      final order = CourierWorkOrder.fromFirestore('o1', {
        'status': 'departed',
        'destinationLatitude': 41,
        'destinationLongitude': 29.5,
        'marketplaceProvider': 'getir',
        'marketplaceOrderCode': '77',
        'switchboardPhone': '02123653403',
      });
      expect(order.destinationLatitude, 41.0);
      expect(order.source, CourierOrderSource.getir);
      expect(courierCallPlan(order)!.uri.toString(), 'tel:02123653403,,77%23');
    });
  });
}
