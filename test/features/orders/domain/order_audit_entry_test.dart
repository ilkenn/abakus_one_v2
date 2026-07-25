import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_actor.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_audit_entry.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_status.dart';

void main() {
  test('OrderAuditChangeType beklenen tum turleri icerir', () {
    expect(OrderAuditChangeType.values, [
      OrderAuditChangeType.statusChange,
      OrderAuditChangeType.priceChange,
      OrderAuditChangeType.manualAdjustment,
    ]);
  });

  test('OrderAuditEntry.statusChange gecis bilgisini dogru kaydeder', () {
    final at = DateTime(2026, 7, 20, 12, 5);

    final entry = OrderAuditEntry.statusChange(
      id: 'audit_1',
      from: OrderStatus.confirmed,
      to: OrderStatus.preparing,
      actor: OrderActor.kitchen,
      at: at,
    );

    expect(entry.type, OrderAuditChangeType.statusChange);
    expect(entry.actor, OrderActor.kitchen);
    expect(entry.timestamp, at);
    expect(entry.previousValue, 'confirmed');
    expect(entry.newValue, 'preparing');
    expect(entry.description, contains('confirmed'));
    expect(entry.description, contains('preparing'));
  });

  test('manuel fiyat degisikligi genel constructor ile kaydedilebilir', () {
    final entry = OrderAuditEntry(
      id: 'audit_2',
      type: OrderAuditChangeType.priceChange,
      description: 'Personel indirimi uygulandi',
      actor: OrderActor.staff,
      timestamp: DateTime(2026, 7, 20, 13, 0),
      previousValue: '150.0',
      newValue: '130.0',
    );

    expect(entry.type, OrderAuditChangeType.priceChange);
    expect(entry.previousValue, '150.0');
    expect(entry.newValue, '130.0');
  });

  test('copyWith yalnizca verilen alanlari degistirir', () {
    final original = OrderAuditEntry(
      id: 'audit_3',
      type: OrderAuditChangeType.manualAdjustment,
      description: 'Not eklendi',
      actor: OrderActor.staff,
      timestamp: DateTime(2026, 7, 20, 13, 0),
    );

    final updated = original.copyWith(description: 'Not guncellendi');

    expect(updated.description, 'Not guncellendi');
    expect(updated.id, original.id);
    expect(updated.actor, original.actor);
  });
}
