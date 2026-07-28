import '../../../orders/domain/models/order_channel.dart';
import '../../../orders/domain/pricing/price_breakdown.dart';
import '../../../../shared/models/money.dart';
import 'discount_snapshot.dart';
import 'pos_order_line_draft.dart';

/// An immutable, in-progress POS order — the cashier's working "cart" for
/// one customer/table, from [openedAt] until it's either submitted
/// ([SubmitPosOrder]) or discarded ([CancelPosOrderSession]).
///
/// **Not** `OrderModel` and **not** the shared `Order` aggregate — this is
/// the write-side, editable session; `SubmitPosOrder`/`CartToOrderMapper`
/// freeze it into an `Order` only once the cashier submits (approved
/// architecture decision, Phase 3 Sprint 3B).
///
/// [lines] is a list of [PosOrderLineDraft] (Phase 3 Sprint 3C) — each
/// wrapping the customer app's own `CartItem` with a stable, session-local
/// id, so line-targeted operations (quantity update, remove, a line
/// discount's `targetOrderLineId`) never depend on array position. This
/// session's own state is fully isolated from the customer-facing
/// `cartProvider`/`CartNotifier`: a cashier's in-progress order never
/// reads or writes the customer app's cart.
///
/// [discounts] replaces the single `discount` field from Sprint 3B — an
/// immutable list of [DiscountSnapshot]s, at most one per line
/// (`targetOrderLineId`) and at most one order-scoped (see
/// `docs/decisions.md` ADR-012). `SetPosDiscount` is the only use case
/// allowed to mutate this list, and always replaces rather than stacks.
///
/// [openedByStaffId] is the **canonical** staff-identity field — there is
/// deliberately no second `staffId` field anywhere on this class.
class PosOrderSession {
  /// Builds a session, defensively copying [lines]/[discounts] into
  /// unmodifiable lists so a caller's later mutation of the list they
  /// passed in can never reach back into this (supposedly immutable)
  /// session.
  factory PosOrderSession({
    required String sessionId,
    required DateTime openedAt,
    required DateTime lastUpdatedAt,
    required String openedByStaffId,
    required String branchId,
    required OrderChannel channel,
    String? tableId,
    String? tableSessionId,
    List<PosOrderLineDraft> lines = const [],
    String customerNote = '',
    String kitchenNote = '',
    List<DiscountSnapshot> discounts = const [],
    required Money fees,
    required Money tip,
    required PriceBreakdown pricing,
  }) {
    return PosOrderSession._(
      sessionId: sessionId,
      openedAt: openedAt,
      lastUpdatedAt: lastUpdatedAt,
      openedByStaffId: openedByStaffId,
      branchId: branchId,
      channel: channel,
      tableId: tableId,
      tableSessionId: tableSessionId,
      lines: List.unmodifiable(lines),
      customerNote: customerNote,
      kitchenNote: kitchenNote,
      discounts: List.unmodifiable(discounts),
      fees: fees,
      tip: tip,
      pricing: pricing,
    );
  }

  const PosOrderSession._({
    required this.sessionId,
    required this.openedAt,
    required this.lastUpdatedAt,
    required this.openedByStaffId,
    required this.branchId,
    required this.channel,
    this.tableId,
    this.tableSessionId,
    required this.lines,
    required this.customerNote,
    required this.kitchenNote,
    required this.discounts,
    required this.fees,
    required this.tip,
    required this.pricing,
  });

  /// Externally supplied — no session-id generation lives in this class,
  /// matching `OrderId`/`OrderNumber`/`Receipt.receiptNumber`'s existing
  /// "externally supplied" convention. Also used as the draft key
  /// (`PosOrderRepository.saveDraft`/`getDraft`/`deleteDraft`) — a session
  /// and its draft share one identity, not two.
  final String sessionId;

  /// Never changes after the session is opened — only [StartPosOrder]
  /// sets it; every other use case's `copyWith` must always pass this
  /// field back unchanged.
  final DateTime openedAt;

  /// Bumped by every successful mutation, via an injected `Clock` — never
  /// `DateTime.now()` called directly.
  final DateTime lastUpdatedAt;

  /// The canonical staff-identity field. No duplicate `staffId` field
  /// exists on this class — every reference to "which cashier" reads this.
  final String openedByStaffId;

  final String branchId;
  final OrderChannel channel;
  final String? tableId;
  final String? tableSessionId;

  /// Defensively copied to an unmodifiable list at construction — see the
  /// factory constructor's own doc comment.
  final List<PosOrderLineDraft> lines;

  /// Order-level notes — distinct from any individual line's own note
  /// (`CartItem.note`, which becomes `OrderLine.customerNote` per line).
  final String customerNote;

  /// Order-level kitchen instruction — distinct from any individual
  /// line's own kitchen note.
  final String kitchenNote;

  /// Every currently-active discount on this session — at most one entry
  /// per `targetOrderLineId`, and at most one with `scope ==
  /// DiscountScope.order`. `SetPosDiscount` enforces both invariants; this
  /// class itself only guarantees the list is defensively copied.
  final List<DiscountSnapshot> discounts;

  /// A single, undifferentiated fee amount — this sprint doesn't split it
  /// into service/delivery/packaging (see `CalculatePosOrderTotals`'s doc
  /// comment for how it's passed through to `PriceCalculator`). Always in
  /// `Currency.accountingCurrency` (TRY) — POS pricing never touches a
  /// foreign currency; only payment does.
  final Money fees;

  final Money tip;

  /// Recomputed by `CalculatePosOrderTotals` after every mutation that
  /// could affect it (lines, discounts, fees, tip) — never grows stale
  /// relative to [lines]/[discounts]/[fees]/[tip].
  final PriceBreakdown pricing;

  /// Delegates to the factory constructor, so every field — including a
  /// new [lines]/[discounts] value — goes through the same defensive-copy
  /// path as initial construction. [openedAt] has no override parameter:
  /// nothing outside [PosOrderSession] itself may change it once set (see
  /// its own doc comment).
  PosOrderSession copyWith({
    DateTime? lastUpdatedAt,
    String? openedByStaffId,
    String? branchId,
    OrderChannel? channel,
    String? tableId,
    bool clearTableId = false,
    String? tableSessionId,
    bool clearTableSessionId = false,
    List<PosOrderLineDraft>? lines,
    String? customerNote,
    String? kitchenNote,
    List<DiscountSnapshot>? discounts,
    Money? fees,
    Money? tip,
    PriceBreakdown? pricing,
  }) {
    return PosOrderSession(
      sessionId: sessionId,
      openedAt: openedAt,
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
      openedByStaffId: openedByStaffId ?? this.openedByStaffId,
      branchId: branchId ?? this.branchId,
      channel: channel ?? this.channel,
      tableId: clearTableId ? null : (tableId ?? this.tableId),
      tableSessionId: clearTableSessionId
          ? null
          : (tableSessionId ?? this.tableSessionId),
      lines: lines ?? this.lines,
      customerNote: customerNote ?? this.customerNote,
      kitchenNote: kitchenNote ?? this.kitchenNote,
      discounts: discounts ?? this.discounts,
      fees: fees ?? this.fees,
      tip: tip ?? this.tip,
      pricing: pricing ?? this.pricing,
    );
  }
}
