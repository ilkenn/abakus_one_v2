import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/mark_kitchen_ticket_line_ready.dart';
import 'package:abakus_one_v2/features/pos/data/kitchen_ticket_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/kitchen/kitchen_ticket.dart';
import 'package:abakus_one_v2/features/pos/domain/kitchen/kitchen_ticket_header.dart';
import 'package:abakus_one_v2/features/pos/domain/kitchen/kitchen_ticket_line.dart';
import 'package:abakus_one_v2/features/pos/domain/kitchen/kitchen_ticket_type.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_clock.dart';

KitchenTicket _ticket() {
  return KitchenTicket(
    id: 'ticket-1',
    orderId: OrderId('order-1'),
    branchId: 'branch-1',
    type: KitchenTicketType.initial,
    header: KitchenTicketHeader(
      restaurantName: 'Abaküs',
      branchName: 'Kadıköy',
      channelLabel: 'Masa',
      orderNumber: 'A-001',
      orderTypeLabel: 'Masa',
      receivedAt: DateTime(2026, 7, 29),
    ),
    lines: const [
      KitchenTicketLine(id: 'line-1', productName: 'Bowl A', quantity: 1),
      KitchenTicketLine(id: 'line-2', productName: 'Bowl B', quantity: 1),
    ],
    firedAt: DateTime(2026, 7, 29),
    revision: 1,
  );
}

void main() {
  test('marks one line ready without completing the whole ticket', () async {
    final repository = InMemoryKitchenTicketRepository();
    await repository.save(_ticket());
    final useCase = MarkKitchenTicketLineReady(
      clock: FakeClock(DateTime(2026, 7, 29, 12)),
      repository: repository,
    );

    final result = await useCase(ticketId: 'ticket-1', lineId: 'line-1');

    expect(result.completedLineIds, ['line-1']);
    expect(result.isFullyReady, isFalse);
    expect(result.orderReadyAt, isNull);
  });

  test('sets orderReadyAt once every line is marked ready', () async {
    final repository = InMemoryKitchenTicketRepository();
    await repository.save(_ticket());
    final useCase = MarkKitchenTicketLineReady(
      clock: FakeClock(DateTime(2026, 7, 29, 12)),
      repository: repository,
    );

    await useCase(ticketId: 'ticket-1', lineId: 'line-1');
    final result = await useCase(ticketId: 'ticket-1', lineId: 'line-2');

    expect(result.isFullyReady, isTrue);
    expect(result.orderReadyAt, DateTime(2026, 7, 29, 12));
  });

  test('marking an already-ready line again is a no-op', () async {
    final repository = InMemoryKitchenTicketRepository();
    await repository.save(_ticket());
    final useCase = MarkKitchenTicketLineReady(
      clock: FakeClock(DateTime(2026, 7, 29, 12)),
      repository: repository,
    );

    final first = await useCase(ticketId: 'ticket-1', lineId: 'line-1');
    final second = await useCase(ticketId: 'ticket-1', lineId: 'line-1');

    expect(second.revision, first.revision);
  });

  test('throws for an unknown line id', () async {
    final repository = InMemoryKitchenTicketRepository();
    await repository.save(_ticket());
    final useCase = MarkKitchenTicketLineReady(
      clock: FakeClock(DateTime(2026, 7, 29)),
      repository: repository,
    );

    expect(
      () => useCase(ticketId: 'ticket-1', lineId: 'missing'),
      throwsA(isA<UnknownRestaurantOperationsEntityViolation>()),
    );
  });
}
