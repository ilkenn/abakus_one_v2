import '../../../orders/domain/fulfillment/package_preparation.dart';
import '../../../orders/domain/models/order_id.dart';
import '../kitchen/kitchen_ticket.dart';
import 'expeditor_entry.dart';

/// Builds the expeditor's [ExpeditorEntry] list from already-fetched
/// [KitchenTicket]s and [PackagePreparation]s — a pure function, no
/// repository access of its own (the caller/controller fetches both lists
/// and passes them in), mirroring `ForeignCurrencyEquivalentsCalculator`'s
/// "pure computation over already-loaded data" shape.
///
/// One order can have multiple tickets (initial + delta + cancellation) —
/// they're aggregated per [OrderId], not shown as separate entries: the
/// expeditor cares about "is this order ready to go out," not which
/// individual ticket a line came from.
abstract final class ExpeditorProjectionBuilder {
  ExpeditorProjectionBuilder._();

  static List<ExpeditorEntry> build({
    required List<KitchenTicket> tickets,
    required List<PackagePreparation> packagePreparations,
  }) {
    final ticketsByOrder = <String, List<KitchenTicket>>{};
    for (final ticket in tickets) {
      ticketsByOrder.putIfAbsent(ticket.orderId.value, () => []).add(ticket);
    }

    final packageByOrder = <String, PackagePreparation>{
      for (final preparation in packagePreparations)
        preparation.orderId.value: preparation,
    };

    final entries = <ExpeditorEntry>[];
    for (final entry in ticketsByOrder.entries) {
      final orderTickets = entry.value;
      var pending = 0;
      var ready = 0;
      DateTime? latestReadySince;
      for (final ticket in orderTickets) {
        ready += ticket.completedLineIds.length;
        pending += ticket.lines.length - ticket.completedLineIds.length;
        if (ticket.orderReadyAt != null &&
            (latestReadySince == null ||
                ticket.orderReadyAt!.isAfter(latestReadySince))) {
          latestReadySince = ticket.orderReadyAt;
        }
      }
      final isOrderReady = orderTickets.every((t) => t.isFullyReady);

      entries.add(ExpeditorEntry(
        orderId: orderTickets.first.orderId,
        orderNumber: orderTickets.first.header.orderNumber,
        pendingLineCount: pending,
        readyLineCount: ready,
        isOrderReady: isOrderReady,
        readySince: isOrderReady ? latestReadySince : null,
        packageStatus: packageByOrder[entry.key]?.status,
      ));
    }
    return entries;
  }
}
