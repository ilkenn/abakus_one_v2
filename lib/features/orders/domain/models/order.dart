import '../../../../core/errors/business_rule_violation.dart';
import '../pricing/price_breakdown.dart';
import 'courier_visibility.dart';
import 'order_actor.dart';
import 'order_audit_entry.dart';
import 'order_channel.dart';
import 'order_id.dart';
import 'order_line.dart';
import 'order_number.dart';
import 'order_status.dart';
import 'order_timestamps.dart';

/// The shared order aggregate — the domain foundation POS, Kitchen Display,
/// Courier, Customer App, and Admin are all meant to build on.
///
/// **Deliberately a new, separate type from the legacy `OrderModel`**
/// (`order_model.dart`) — approved architecture decision, Phase 3
/// Sprint 3A. `OrderModel` mixes the canonical lifecycle fields with a
/// large block of customer-app-specific UI fields (delivery-instruction
/// flags, review/rating fields, ...) that have no place in an aggregate
/// meant to be shared across every channel and every staff-facing surface.
/// This sprint does not migrate or replace `OrderModel`; that's separate,
/// future, out-of-scope work.
///
/// Reuses every existing shared building block rather than duplicating
/// one: [OrderStatus]/`OrderStatusTransitions` (the 11-state machine),
/// [OrderChannel], [OrderActor], [CourierVisibility], [OrderTimestamps],
/// and [OrderAuditEntry] — the last of these **is** this aggregate's
/// immutable status history (see [statusHistory]'s doc comment); no
/// second, parallel history type was introduced.
class Order {
  const Order({
    required this.id,
    required this.orderNumber,
    required this.status,
    required this.channel,
    required this.branchId,
    required this.restaurantId,
    this.customerId,
    this.tableId,
    this.tableSessionId,
    this.guestSessionId,
    this.courierVisibility = CourierVisibility.hidden,
    required this.lines,
    required this.pricing,
    this.statusHistory = const [],
    this.version = 1,
    required this.timestamps,
    this.customerNote = '',
    this.kitchenNote = '',
  });

  final OrderId id;
  final OrderNumber orderNumber;
  final OrderStatus status;
  final OrderChannel channel;

  final String branchId;
  final String restaurantId;

  /// `null` for a guest/anonymous order (e.g. an unauthenticated QR table
  /// visit) — see `GuestSession.authenticatedUserId` for the same
  /// optionality pattern.
  final String? customerId;

  /// Table/session references — all optional, `null` for a channel with
  /// no table context (takeaway, delivery). Field names deliberately match
  /// `TableSession`/`GuestSession`'s own id fields, not new vocabulary.
  final String? tableId;
  final String? tableSessionId;
  final String? guestSessionId;

  /// See [CourierVisibility]'s own doc comment for the privacy rule this
  /// preserves verbatim from the existing customer-app implementation —
  /// reaching [OrderStatus.outForDelivery] alone must never imply this is
  /// [CourierVisibility.visibleToCustomer].
  final CourierVisibility courierVisibility;

  final List<OrderLine> lines;
  final PriceBreakdown pricing;

  /// This aggregate's immutable status history — append-only, one
  /// [OrderAuditEntry.statusChange] per transition made via
  /// [transitionTo]. Deliberately not a second, order-specific history
  /// type: [OrderAuditEntry] already is exactly this (actor/timestamp/
  /// previous-value/new-value), reused rather than duplicated.
  final List<OrderAuditEntry> statusHistory;

  /// Optimistic-concurrency version, starting at 1 and incrementing by 1
  /// on every [transitionTo] call — groundwork for a future backend sync/
  /// conflict-detection layer, not consumed by anything in this sprint.
  final int version;

  final OrderTimestamps timestamps;

  /// Order-level note from the customer — distinct from any individual
  /// [OrderLine.customerNote]. Empty by default; additive field (Phase 3
  /// Sprint 3B) so every existing caller/test built before it still
  /// compiles and behaves identically.
  final String customerNote;

  /// Order-level instruction for the kitchen — distinct from any
  /// individual [OrderLine.kitchenNote]. Same additive-field reasoning as
  /// [customerNote].
  final String kitchenNote;

  /// Moves this order from [status] to [newStatus], appending a new
  /// [OrderAuditEntry.statusChange] to [statusHistory] and recording the
  /// timestamp via [OrderTimestamps.recordedAt].
  ///
  /// Throws [InvalidOrderStatusTransitionViolation] if
  /// `OrderStatusTransitions.canTransition(status, newStatus)` is `false`
  /// — this is the one and only place an `Order`'s status may change, so
  /// every transition is guaranteed to have gone through that check.
  ///
  /// [auditEntryId] is externally supplied, matching [OrderId]/
  /// [OrderNumber]'s "no ID generation in this codebase" reasoning.
  Order transitionTo(
    OrderStatus newStatus, {
    required OrderActor actor,
    required DateTime at,
    required String auditEntryId,
  }) {
    if (!OrderStatusTransitions.canTransition(status, newStatus)) {
      throw InvalidOrderStatusTransitionViolation(
        fromStatusName: status.name,
        toStatusName: newStatus.name,
      );
    }
    final entry = OrderAuditEntry.statusChange(
      id: auditEntryId,
      from: status,
      to: newStatus,
      actor: actor,
      at: at,
    );
    return copyWith(
      status: newStatus,
      statusHistory: [...statusHistory, entry],
      version: version + 1,
      timestamps: timestamps.recordedAt(newStatus, at),
    );
  }

  Order copyWith({
    OrderId? id,
    OrderNumber? orderNumber,
    OrderStatus? status,
    OrderChannel? channel,
    String? branchId,
    String? restaurantId,
    String? customerId,
    String? tableId,
    String? tableSessionId,
    String? guestSessionId,
    CourierVisibility? courierVisibility,
    List<OrderLine>? lines,
    PriceBreakdown? pricing,
    List<OrderAuditEntry>? statusHistory,
    int? version,
    OrderTimestamps? timestamps,
    String? customerNote,
    String? kitchenNote,
  }) {
    return Order(
      id: id ?? this.id,
      orderNumber: orderNumber ?? this.orderNumber,
      status: status ?? this.status,
      channel: channel ?? this.channel,
      branchId: branchId ?? this.branchId,
      restaurantId: restaurantId ?? this.restaurantId,
      customerId: customerId ?? this.customerId,
      tableId: tableId ?? this.tableId,
      tableSessionId: tableSessionId ?? this.tableSessionId,
      guestSessionId: guestSessionId ?? this.guestSessionId,
      courierVisibility: courierVisibility ?? this.courierVisibility,
      lines: lines ?? this.lines,
      pricing: pricing ?? this.pricing,
      statusHistory: statusHistory ?? this.statusHistory,
      version: version ?? this.version,
      timestamps: timestamps ?? this.timestamps,
      customerNote: customerNote ?? this.customerNote,
      kitchenNote: kitchenNote ?? this.kitchenNote,
    );
  }
}
