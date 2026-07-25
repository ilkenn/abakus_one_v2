import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_model.dart';

void main() {
  test('OrderChannel beklenen tum kanallari icerir', () {
    expect(OrderChannel.values, [
      OrderChannel.dineInQr,
      OrderChannel.dineInStaff,
      OrderChannel.takeaway,
      OrderChannel.delivery,
      OrderChannel.reservationPreorder,
    ]);
  });

  test(
    'channel belirtilmezse OrderModel mevcut teslimat davranisini korur',
    () {
      const order = OrderModel(
        id: 'ORD-TEST-1',
        date: '01.01.2026',
        totalAmount: 100.0,
        status: 'Hazırlanıyor',
      );

      expect(order.channel, OrderChannel.delivery);
    },
  );

  test('copyWith ile channel degistirilebilir', () {
    const order = OrderModel(
      id: 'ORD-TEST-2',
      date: '01.01.2026',
      totalAmount: 50.0,
      status: 'Onay Bekliyor',
    );

    final dineIn = order.copyWith(channel: OrderChannel.dineInQr);

    expect(dineIn.channel, OrderChannel.dineInQr);
    expect(order.channel, OrderChannel.delivery);
  });
}
