import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_status.dart';
import 'package:abakus_one_v2/features/pos/domain/kds/kitchen_order_action_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('primaryActionFor', () {
    test(
        'confirmed -> Hazırlanıyor, preparing -> Hazırlandı on every '
        'lifecycle channel', () {
      for (final channel in [
        OrderChannel.dineInQr,
        OrderChannel.takeaway,
        OrderChannel.delivery,
        OrderChannel.reservationPreorder,
      ]) {
        expect(
            KitchenOrderActionPolicy.primaryActionFor(
                channel, OrderStatus.confirmed),
            KitchenOrderAction.startPreparing);
        expect(
            KitchenOrderActionPolicy.primaryActionFor(
                channel, OrderStatus.preparing),
            KitchenOrderAction.markReady);
      }
    });

    test('ready -> Teslim Edildi for dine-in/reservation/takeaway only', () {
      expect(
          KitchenOrderActionPolicy.primaryActionFor(
              OrderChannel.dineInQr, OrderStatus.ready),
          KitchenOrderAction.handOver);
      expect(
          KitchenOrderActionPolicy.primaryActionFor(
              OrderChannel.reservationPreorder, OrderStatus.ready),
          KitchenOrderAction.handOver);
      expect(
          KitchenOrderActionPolicy.primaryActionFor(
              OrderChannel.takeaway, OrderStatus.ready),
          KitchenOrderAction.handOver);
      expect(
          KitchenOrderActionPolicy.primaryActionFor(
              OrderChannel.delivery, OrderStatus.ready),
          isNull);
    });

    test(
        'no action for pendingConfirmation (stays on POS), unknown status, '
        'or dineInStaff', () {
      expect(
          KitchenOrderActionPolicy.primaryActionFor(
              OrderChannel.dineInQr, OrderStatus.pendingConfirmation),
          isNull);
      expect(
          KitchenOrderActionPolicy.primaryActionFor(
              OrderChannel.dineInQr, null),
          isNull);
      expect(
          KitchenOrderActionPolicy.primaryActionFor(
              OrderChannel.dineInStaff, OrderStatus.confirmed),
          isNull);
    });
  });

  test('handOverTargetFor', () {
    expect(KitchenOrderActionPolicy.handOverTargetFor(OrderChannel.dineInQr),
        OrderStatus.served);
    expect(
        KitchenOrderActionPolicy.handOverTargetFor(
            OrderChannel.reservationPreorder),
        OrderStatus.served);
    expect(KitchenOrderActionPolicy.handOverTargetFor(OrderChannel.takeaway),
        OrderStatus.completed);
    expect(KitchenOrderActionPolicy.handOverTargetFor(OrderChannel.delivery),
        isNull);
  });

  test('canCancel: confirmed/preparing/ready on every lifecycle channel', () {
    for (final channel in [
      OrderChannel.dineInQr,
      OrderChannel.takeaway,
      OrderChannel.delivery,
      OrderChannel.reservationPreorder,
    ]) {
      for (final status in [
        OrderStatus.confirmed,
        OrderStatus.preparing,
        OrderStatus.ready,
      ]) {
        expect(KitchenOrderActionPolicy.canCancel(channel, status), isTrue,
            reason: '${channel.name}/${status.name}');
      }
      expect(KitchenOrderActionPolicy.canCancel(channel, OrderStatus.served),
          isFalse);
    }
    expect(
        KitchenOrderActionPolicy.canCancel(
            OrderChannel.dineInStaff, OrderStatus.confirmed),
        isFalse);
  });
}
