import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/pos/application/identity/kitchen_event_id_generator.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/record_kitchen_event.dart';
import 'package:abakus_one_v2/features/pos/data/in_memory_kitchen_event_bus.dart';
import 'package:abakus_one_v2/features/pos/data/kitchen_event_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/kds/kitchen_line_status.dart';
import 'package:abakus_one_v2/features/pos/domain/kds/kitchen_station.dart';
import 'package:abakus_one_v2/features/pos/domain/kds/kitchen_work_item.dart';
import 'package:abakus_one_v2/features/pos/domain/kitchen/kitchen_ticket.dart';
import 'package:abakus_one_v2/features/pos/domain/kitchen/kitchen_ticket_header.dart';
import 'package:abakus_one_v2/features/pos/domain/kitchen/kitchen_ticket_line.dart';
import 'package:abakus_one_v2/features/pos/domain/kitchen/kitchen_ticket_type.dart';

/// A minimal, valid [KitchenTicket] with [lineCount] lines, for use-case
/// tests that need a real ticket rather than exercising `FireKitchenTicket`
/// itself.
KitchenTicket buildTestKitchenTicket({
  String ticketId = 'ticket-1',
  String orderId = 'order-1',
  String branchId = 'branch-1',
  int lineCount = 1,
  int revision = 1,
}) {
  return KitchenTicket(
    id: ticketId,
    orderId: OrderId(orderId),
    branchId: branchId,
    type: KitchenTicketType.initial,
    header: KitchenTicketHeader(
      restaurantName: 'Abaküs',
      branchName: 'Test Şube',
      channelLabel: 'Masa',
      orderNumber: 'ORD-1',
      orderTypeLabel: 'dineInStaff',
      receivedAt: DateTime(2026, 1, 1, 12),
    ),
    lines: [
      for (var i = 0; i < lineCount; i++)
        KitchenTicketLine(
          id: '$ticketId-line-$i',
          productName: 'Ürün $i',
          quantity: 1,
        ),
    ],
    firedAt: DateTime(2026, 1, 1, 12),
    revision: revision,
  );
}

/// A minimal, valid, queued [KitchenWorkItem] for use-case tests that need
/// a starting point rather than exercising `EnqueueKitchenWorkItems`
/// itself.
KitchenWorkItem buildTestKitchenWorkItem({
  String workItemId = 'work-1',
  String branchId = 'branch-1',
  KitchenStation station = KitchenStation.shared,
  String orderId = 'order-1',
  String kitchenTicketId = 'ticket-1',
  String kitchenTicketLineId = 'ticket-1-line-0',
  int quantity = 1,
  int readyQuantity = 0,
  KitchenLineStatus status = KitchenLineStatus.queued,
  int revision = 1,
  DateTime? preparingStartedAt,
}) {
  return KitchenWorkItem(
    id: workItemId,
    branchId: branchId,
    station: station,
    orderId: OrderId(orderId),
    kitchenTicketId: kitchenTicketId,
    kitchenTicketLineId: kitchenTicketLineId,
    quantity: quantity,
    readyQuantity: readyQuantity,
    status: status,
    queuedAt: DateTime(2026, 1, 1, 12),
    preparingStartedAt: preparingStartedAt,
    revision: revision,
    idempotencyKey: '$kitchenTicketId-$kitchenTicketLineId',
  );
}

/// A [RecordKitchenEvent] wired to fresh in-memory infrastructure — for
/// use-case tests that need one but aren't testing the event
/// repository/bus themselves.
RecordKitchenEvent buildTestRecordKitchenEvent({
  KitchenEventRepository? eventRepository,
}) {
  return RecordKitchenEvent(
    idGenerator: SequentialKitchenEventIdGenerator(),
    eventRepository: eventRepository ?? InMemoryKitchenEventRepository(),
    eventPublisher: InMemoryKitchenEventBus(),
  );
}
