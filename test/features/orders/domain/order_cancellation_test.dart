import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_actor.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_cancellation.dart';

void main() {
  test('OrderActor beklenen tum aktorleri icerir', () {
    expect(OrderActor.values, [
      OrderActor.customer,
      OrderActor.staff,
      OrderActor.kitchen,
      OrderActor.system,
    ]);
  });

  test('OrderCancellationInfo reason/actor/timestamp bilgisini tasir', () {
    final timestamp = DateTime(2026, 7, 20, 14, 30);
    final cancellation = OrderCancellationInfo(
      reason: 'Musteri vazgecti',
      actor: OrderActor.customer,
      timestamp: timestamp,
    );

    expect(cancellation.reason, 'Musteri vazgecti');
    expect(cancellation.actor, OrderActor.customer);
    expect(cancellation.timestamp, timestamp);
  });

  test('copyWith yalnizca verilen alanlari degistirir', () {
    final original = OrderCancellationInfo(
      reason: 'Stok yok',
      actor: OrderActor.kitchen,
      timestamp: DateTime(2026, 7, 20, 12, 0),
    );

    final updated = original.copyWith(actor: OrderActor.system);

    expect(updated.actor, OrderActor.system);
    expect(updated.reason, original.reason);
    expect(updated.timestamp, original.timestamp);
  });
}
