import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/pos/data/kitchen_ticket_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/kitchen/kitchen_ticket.dart';
import 'package:abakus_one_v2/features/pos/domain/kitchen/kitchen_ticket_header.dart';
import 'package:abakus_one_v2/features/pos/domain/kitchen/kitchen_ticket_type.dart';
import 'package:flutter_test/flutter_test.dart';

KitchenTicket _ticket({
  String id = 'ticket-1',
  String orderId = 'order-1',
  String branchId = 'branch-1',
  DateTime? firedAt,
}) {
  return KitchenTicket(
    id: id,
    orderId: OrderId(orderId),
    branchId: branchId,
    type: KitchenTicketType.initial,
    header: KitchenTicketHeader(
      restaurantName: 'Abaküs',
      branchName: 'Kadıköy',
      channelLabel: 'Masa',
      orderNumber: 'A-001',
      orderTypeLabel: 'Masa',
      receivedAt: DateTime(2026, 7, 29),
    ),
    lines: const [],
    firedAt: firedAt ?? DateTime(2026, 7, 29),
    revision: 1,
  );
}

void main() {
  test('findById returns the latest revision', () async {
    final repository = InMemoryKitchenTicketRepository();
    await repository.save(_ticket());
    await repository.save(_ticket().copyWith(revision: 2, isCopy: true));

    final result = await repository.findById('ticket-1');
    expect(result!.revision, 2);
    expect(result.isCopy, isTrue);
  });

  test('findByOrderId returns every ticket fired for that order, oldest first',
      () async {
    final repository = InMemoryKitchenTicketRepository();
    await repository.save(_ticket(
        id: 'ticket-1',
        orderId: 'order-1',
        firedAt: DateTime(2026, 7, 29, 10)));
    await repository.save(_ticket(
        id: 'ticket-2',
        orderId: 'order-1',
        firedAt: DateTime(2026, 7, 29, 11)));
    await repository.save(_ticket(id: 'ticket-3', orderId: 'order-2'));

    final results = await repository.findByOrderId(OrderId('order-1'));

    expect(results.map((t) => t.id), ['ticket-1', 'ticket-2']);
  });

  test(
      'findActiveByBranch returns the latest revision of every ticket for that branch',
      () async {
    final repository = InMemoryKitchenTicketRepository();
    await repository.save(_ticket(id: 'ticket-1', branchId: 'branch-a'));
    await repository.save(_ticket(id: 'ticket-2', branchId: 'branch-b'));

    final results = await repository.findActiveByBranch('branch-a');

    expect(results.map((t) => t.id), ['ticket-1']);
  });
}
