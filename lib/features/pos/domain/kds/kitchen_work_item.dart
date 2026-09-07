import '../../../orders/domain/models/order_id.dart';
import 'kitchen_line_status.dart';
import 'kitchen_station.dart';

/// One routed, station-scoped unit of kitchen work, derived from a single
/// [KitchenTicketLine] — the coordination record a KDS screen actually
/// queues and acts on. **Not a duplicate of `KitchenTicket`/`KitchenTicketLine`**:
/// it never re-stores product name/ingredients/notes (still read from the
/// source `KitchenTicketLine` via [kitchenTicketId]/[kitchenTicketLineId]
/// when a screen needs them) — it only tracks the richer preparation
/// lifecycle ([KitchenLineStatus]) and routing/sync metadata Phase 3's
/// binary not-ready/ready tracking doesn't carry.
///
/// **Append-only**: never mutated in place — every transition produces a
/// new instance with the same [id] and an incremented [revision],
/// mirroring `CashSession`/`CourierSettlementSession`'s shape.
class KitchenWorkItem {
  const KitchenWorkItem({
    required this.id,
    required this.branchId,
    required this.station,
    required this.orderId,
    required this.kitchenTicketId,
    required this.kitchenTicketLineId,
    required this.quantity,
    this.readyQuantity = 0,
    required this.status,
    required this.queuedAt,
    this.acknowledgedAt,
    this.preparingStartedAt,
    this.readyAt,
    this.cancelledAt,
    this.unavailableAt,
    this.recalledAt,
    this.wastedAt,
    required this.revision,
    required this.idempotencyKey,
    this.sourceEventId,
  });

  /// Externally supplied, like every other identifier in this codebase.
  final String id;

  final String branchId;
  final KitchenStation station;
  final OrderId orderId;
  final String kitchenTicketId;

  /// References `KitchenTicketLine.id` (ticket-scoped, not `OrderLine`'s —
  /// `OrderLine` has no stable id at all; see `docs/decisions.md` ADR-013).
  final String kitchenTicketLineId;

  /// The ordered quantity for this line, copied once from the source
  /// `KitchenTicketLine.quantity` at enqueue time (a frozen snapshot, not
  /// a live reference).
  final int quantity;

  /// How much of [quantity] has been marked ready so far — supports
  /// quantity-level completion (e.g. 2 of 3 burgers ready) independently
  /// of the line's own [status], which only reaches [KitchenLineStatus.ready]
  /// once `readyQuantity >= quantity`.
  final int readyQuantity;

  final KitchenLineStatus status;

  final DateTime queuedAt;
  final DateTime? acknowledgedAt;
  final DateTime? preparingStartedAt;
  final DateTime? readyAt;
  final DateTime? cancelledAt;
  final DateTime? unavailableAt;
  final DateTime? recalledAt;
  final DateTime? wastedAt;

  /// Optimistic-concurrency counter — starts at 1.
  final int revision;

  /// Deterministic per (ticket, line) — `'<kitchenTicketId>-<kitchenTicketLineId>'`
  /// — what `EnqueueKitchenWorkItems` checks before creating a new item, so
  /// a duplicate delta/re-fire never creates duplicate kitchen work.
  final String idempotencyKey;

  /// The `KitchenEvent.id` that produced this revision, if any — `null`
  /// for the item's own initial enqueue in some call paths, populated by
  /// every subsequent transition use case.
  final String? sourceEventId;

  bool get isTerminal =>
      status == KitchenLineStatus.cancelled ||
      status == KitchenLineStatus.unavailable ||
      status == KitchenLineStatus.wasted;

  KitchenWorkItem copyWith({
    int? readyQuantity,
    KitchenLineStatus? status,
    DateTime? acknowledgedAt,
    DateTime? preparingStartedAt,
    DateTime? readyAt,
    DateTime? cancelledAt,
    DateTime? unavailableAt,
    DateTime? recalledAt,
    DateTime? wastedAt,
    int? revision,
    String? sourceEventId,
  }) {
    return KitchenWorkItem(
      id: id,
      branchId: branchId,
      station: station,
      orderId: orderId,
      kitchenTicketId: kitchenTicketId,
      kitchenTicketLineId: kitchenTicketLineId,
      quantity: quantity,
      readyQuantity: readyQuantity ?? this.readyQuantity,
      status: status ?? this.status,
      queuedAt: queuedAt,
      acknowledgedAt: acknowledgedAt ?? this.acknowledgedAt,
      preparingStartedAt: preparingStartedAt ?? this.preparingStartedAt,
      readyAt: readyAt ?? this.readyAt,
      cancelledAt: cancelledAt ?? this.cancelledAt,
      unavailableAt: unavailableAt ?? this.unavailableAt,
      recalledAt: recalledAt ?? this.recalledAt,
      wastedAt: wastedAt ?? this.wastedAt,
      revision: revision ?? this.revision,
      idempotencyKey: idempotencyKey,
      sourceEventId: sourceEventId ?? this.sourceEventId,
    );
  }
}
