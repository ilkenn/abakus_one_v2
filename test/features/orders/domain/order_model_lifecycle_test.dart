import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_actor.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_audit_entry.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_cancellation.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_item_snapshot.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_model.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_status.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_timestamps.dart';

void main() {
  test(
    'yeni alanlar belirtilmezse mevcut siparis davranisi degismez (geriye donuk uyumluluk)',
    () {
      const order = OrderModel(
        id: 'ORD-TEST-1',
        date: '01.01.2026',
        totalAmount: 100.0,
        status: 'Hazırlanıyor',
      );

      expect(order.channel, OrderChannel.delivery);
      expect(order.lifecycleStatus, OrderStatus.created);
      expect(order.items, isEmpty);
      expect(order.requestId, '');
      expect(order.createdDeviceId, '');
      expect(order.createdSessionId, '');
      expect(order.timestamps, isNull);
      expect(order.cancellation, isNull);
      expect(order.auditTrail, isEmpty);
      // Mevcut alan (legacy status string) hala oldugu gibi calisir.
      expect(order.status, 'Hazırlanıyor');
    },
  );

  test(
      'bir dine-in QR siparisi kanal ve yasam dongusu durumunu birlikte tasiyabilir',
      () {
    const order = OrderModel(
      id: 'ORD-TEST-2',
      date: '20.07.2026',
      totalAmount: 250.0,
      status: 'Onay Bekliyor',
      channel: OrderChannel.dineInQr,
      lifecycleStatus: OrderStatus.pendingConfirmation,
      items: [
        OrderItemSnapshot(
          productId: 'prod_1',
          productName: 'Protein Bowl',
          quantity: 2,
          unitPrice: 125.0,
        ),
      ],
      requestId: 'req_abc123',
      createdDeviceId: 'device_1',
      createdSessionId: 'guest_session_1',
    );

    expect(order.channel, OrderChannel.dineInQr);
    expect(order.lifecycleStatus, OrderStatus.pendingConfirmation);
    expect(order.items, hasLength(1));
    expect(order.items.first.lineTotal, 250.0);
    expect(order.requestId, 'req_abc123');
    expect(order.createdSessionId, 'guest_session_1');
  });

  test('copyWith ile yasam dongusu ilerletilebilir ve gecmis izlenebilir', () {
    const initial = OrderModel(
      id: 'ORD-TEST-3',
      date: '20.07.2026',
      totalAmount: 180.0,
      status: 'Onay Bekliyor',
      channel: OrderChannel.takeaway,
      lifecycleStatus: OrderStatus.pendingConfirmation,
    );

    final confirmedAt = DateTime(2026, 7, 20, 12, 5);
    final confirmed = initial.copyWith(
      lifecycleStatus: OrderStatus.confirmed,
      timestamps: OrderTimestamps(
        created: DateTime(2026, 7, 20, 12, 0),
      ).recordedAt(OrderStatus.confirmed, confirmedAt),
      auditTrail: [
        OrderAuditEntry.statusChange(
          id: 'audit_1',
          from: OrderStatus.pendingConfirmation,
          to: OrderStatus.confirmed,
          actor: OrderActor.staff,
          at: confirmedAt,
        ),
      ],
    );

    expect(confirmed.lifecycleStatus, OrderStatus.confirmed);
    expect(confirmed.timestamps?.confirmed, confirmedAt);
    expect(confirmed.auditTrail, hasLength(1));
    expect(confirmed.auditTrail.first.newValue, 'confirmed');
    // Orijinal siparis degismedi.
    expect(initial.lifecycleStatus, OrderStatus.pendingConfirmation);
    expect(initial.auditTrail, isEmpty);
  });

  test('iptal edilen siparis yapisal iptal metadatasi tasir', () {
    const initial = OrderModel(
      id: 'ORD-TEST-4',
      date: '20.07.2026',
      totalAmount: 90.0,
      status: 'İptal Edildi',
      lifecycleStatus: OrderStatus.preparing,
    );

    final cancelledAt = DateTime(2026, 7, 20, 12, 10);
    final cancelled = initial.copyWith(
      lifecycleStatus: OrderStatus.cancelled,
      cancellation: OrderCancellationInfo(
        reason: 'Mutfak malzeme yetersizligi',
        actor: OrderActor.kitchen,
        timestamp: cancelledAt,
      ),
    );

    expect(cancelled.lifecycleStatus, OrderStatus.cancelled);
    expect(cancelled.cancellation, isNotNull);
    expect(cancelled.cancellation!.actor, OrderActor.kitchen);
    expect(cancelled.cancellation!.timestamp, cancelledAt);
    // Eski (legacy) alanlar bu fazda dokunulmadan kaldi.
    expect(cancelled.cancellationReason, isNull);
  });
}
