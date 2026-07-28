import 'package:abakus_one_v2/features/orders/domain/fulfillment/package_preparation.dart';
import 'package:abakus_one_v2/features/orders/domain/fulfillment/package_preparation_status.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/pos/domain/expeditor/expeditor_projection_builder.dart';
import 'package:abakus_one_v2/features/pos/domain/kitchen/kitchen_ticket.dart';
import 'package:abakus_one_v2/features/pos/domain/kitchen/kitchen_ticket_header.dart';
import 'package:abakus_one_v2/features/pos/domain/kitchen/kitchen_ticket_line.dart';
import 'package:abakus_one_v2/features/pos/domain/kitchen/kitchen_ticket_type.dart';
import 'package:flutter_test/flutter_test.dart';

KitchenTicketHeader _header() {
  return KitchenTicketHeader(
    restaurantName: 'Abaküs',
    branchName: 'Kadıköy',
    channelLabel: 'Masa',
    orderNumber: 'A-001',
    orderTypeLabel: 'Masa',
    receivedAt: DateTime(2026, 7, 29),
  );
}

void main() {
  test('aggregates pending/ready counts across multiple tickets for one order',
      () {
    final orderId = OrderId('order-1');
    final initial = KitchenTicket(
      id: 'ticket-1',
      orderId: orderId,
      branchId: 'branch-1',
      type: KitchenTicketType.initial,
      header: _header(),
      lines: const [
        KitchenTicketLine(id: 'line-1', productName: 'Bowl A', quantity: 1),
      ],
      completedLineIds: const ['line-1'],
      orderReadyAt: DateTime(2026, 7, 29, 12),
      firedAt: DateTime(2026, 7, 29),
      revision: 2,
    );
    final delta = KitchenTicket(
      id: 'ticket-2',
      orderId: orderId,
      branchId: 'branch-1',
      type: KitchenTicketType.delta,
      header: _header(),
      lines: const [
        KitchenTicketLine(id: 'line-2', productName: 'Bowl B', quantity: 1),
      ],
      firedAt: DateTime(2026, 7, 29, 12, 5),
      revision: 1,
    );

    final entries = ExpeditorProjectionBuilder.build(
      tickets: [initial, delta],
      packagePreparations: const [],
    );

    expect(entries, hasLength(1));
    final entry = entries.single;
    expect(entry.readyLineCount, 1);
    expect(entry.pendingLineCount, 1);
    // Not every ticket is fully ready (the delta ticket isn't), so the
    // order overall isn't ready yet, even though the initial ticket is.
    expect(entry.isOrderReady, isFalse);
    expect(entry.readySince, isNull);
  });

  test('isOrderReady and readySince once every ticket is fully ready', () {
    final orderId = OrderId('order-1');
    final ticket = KitchenTicket(
      id: 'ticket-1',
      orderId: orderId,
      branchId: 'branch-1',
      type: KitchenTicketType.initial,
      header: _header(),
      lines: const [
        KitchenTicketLine(id: 'line-1', productName: 'Bowl A', quantity: 1),
      ],
      completedLineIds: const ['line-1'],
      orderReadyAt: DateTime(2026, 7, 29, 12),
      firedAt: DateTime(2026, 7, 29),
      revision: 2,
    );

    final entries = ExpeditorProjectionBuilder.build(
      tickets: [ticket],
      packagePreparations: [
        PackagePreparation(
          orderId: orderId,
          status: PackagePreparationStatus.packing,
          revision: 1,
        ),
      ],
    );

    expect(entries.single.isOrderReady, isTrue);
    expect(entries.single.readySince, DateTime(2026, 7, 29, 12));
    expect(entries.single.packageStatus, PackagePreparationStatus.packing);
  });
}
