import 'package:abakus_one_v2/features/orders/domain/models/order_actor.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/pos/data/closure_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/audit/closure_audit_entry.dart';
import 'package:abakus_one_v2/features/pos/domain/audit/closure_audit_event_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InMemoryClosureAuditEntryRepository', () {
    test('appendEvent then findByOrderId returns events oldest first',
        () async {
      final repository = InMemoryClosureAuditEntryRepository();
      final orderId = OrderId('order-1');

      await repository.appendEvent(
        orderId,
        ClosureAuditEntry(
          id: 'a1',
          type: ClosureAuditEventType.paymentCompleted,
          description: 'Payment completed',
          actor: OrderActor.staff,
          timestamp: DateTime(2026, 7, 29, 12, 0),
        ),
      );
      await repository.appendEvent(
        orderId,
        ClosureAuditEntry(
          id: 'a2',
          type: ClosureAuditEventType.orderClosed,
          description: 'Order closed',
          actor: OrderActor.staff,
          timestamp: DateTime(2026, 7, 29, 12, 1),
        ),
      );

      final events = await repository.findByOrderId(orderId);

      expect(events, hasLength(2));
      expect(events.first.id, 'a1');
      expect(events.last.id, 'a2');
    });

    test('events for different orders never mix', () async {
      final repository = InMemoryClosureAuditEntryRepository();
      await repository.appendEvent(
        OrderId('order-1'),
        ClosureAuditEntry(
          id: 'a1',
          type: ClosureAuditEventType.orderClosed,
          description: 'Order closed',
          actor: OrderActor.staff,
          timestamp: DateTime(2026, 7, 29),
        ),
      );

      final eventsForOtherOrder =
          await repository.findByOrderId(OrderId('order-2'));

      expect(eventsForOtherOrder, isEmpty);
    });

    test('returns an unmodifiable list', () async {
      final repository = InMemoryClosureAuditEntryRepository();
      final events = await repository.findByOrderId(OrderId('order-1'));

      expect(() => events.add(events.isEmpty ? _sampleEntry() : events.first),
          throwsUnsupportedError);
    });
  });
}

ClosureAuditEntry _sampleEntry() {
  return ClosureAuditEntry(
    id: 'a1',
    type: ClosureAuditEventType.orderClosed,
    description: 'x',
    actor: OrderActor.staff,
    timestamp: DateTime(2026, 7, 29),
  );
}
