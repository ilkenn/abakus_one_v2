import '../../../orders/domain/discounts/discount.dart';
import '../../../orders/domain/models/order_channel.dart';
import '../../../orders/domain/pricing/price_breakdown.dart';
import '../../../cart/domain/models/cart_item.dart';
import '../../../../shared/models/money.dart';

/// An immutable, in-progress POS order — the cashier's working "cart" for
/// one customer/table, from [openedAt] until it's either submitted
/// ([SubmitPosOrder]) or discarded ([CancelPosOrderSession]).
///
/// **Not** `OrderModel` and **not** the shared `Order` aggregate — this is
/// the write-side, editable session; `SubmitPosOrder`/`CartToOrderMapper`
/// freeze it into an `Order` only once the cashier submits (approved
/// architecture decision, Phase 3 Sprint 3B).
///
/// [lines] reuses the customer app's own `CartItem` type directly (not a
/// POS-specific line type) — it already carries everything a line needs
/// (product identity, price, modifiers, quantity, note) and is exactly
/// what `CartLineMapper`/`CartToOrderMapper` already accept, so no
/// duplicate cart-line model was introduced. This session's own state is
/// fully isolated from the customer-facing `cartProvider`/`CartNotifier`:
/// a cashier's in-progress order never reads or writes the customer app's
/// cart.
///
/// [openedByStaffId] is the **canonical** staff-identity field — there is
/// deliberately no second `staffId` field anywhere on this class.
class PosOrderSession {
  /// Builds a session, defensively copying [lines] into an unmodifiable
  /// list so a caller's later mutation of the list they passed in can
  /// never reach back into this (supposedly immutable) session.
  factory PosOrderSession({
    required String sessionId,
    required DateTime openedAt,
    required DateTime lastUpdatedAt,
    required String openedByStaffId,
    required String branchId,
    required OrderChannel channel,
    String? tableId,
    String? tableSessionId,
    List<CartItem> lines = const [],
    String customerNote = '',
    String kitchenNote = '',
    Discount? discount,
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
      discount: discount,
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
    this.discount,
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
  final List<CartItem> lines;

  /// Order-level notes — distinct from any individual line's own note
  /// (`CartItem.note`, which becomes `OrderLine.customerNote` per line).
  final String customerNote;

  /// Order-level kitchen instruction — distinct from any individual
  /// line's own kitchen note.
  final String kitchenNote;

  /// At most one order-level discount — this session's data shape has no
  /// slot for a second one, which is exactly why `DiscountStackingPolicy`
  /// (multiple-discount resolution) isn't invoked here: there's
  /// structurally never more than one candidate to resolve between.
  final Discount? discount;

  /// A single, undifferentiated fee amount — this sprint doesn't split it
  /// into service/delivery/packaging (see `CalculatePosOrderTotals`'s doc
  /// comment for how it's passed through to `PriceCalculator`). Always in
  /// `Currency.accountingCurrency` (TRY) — POS pricing never touches a
  /// foreign currency; only payment does (out of scope this sprint).
  final Money fees;

  final Money tip;

  /// Recomputed by `CalculatePosOrderTotals` after every mutation that
  /// could affect it (lines, discount, fees, tip) — never grows stale
  /// relative to [lines]/[discount]/[fees]/[tip].
  final PriceBreakdown pricing;

  /// Delegates to the factory constructor, so every field — including a
  /// new [lines] value — goes through the same defensive-copy path as
  /// initial construction. [openedAt] has no override parameter: nothing
  /// outside [PosOrderSession] itself may change it once set (see its own
  /// doc comment).
  PosOrderSession copyWith({
    DateTime? lastUpdatedAt,
    String? openedByStaffId,
    String? branchId,
    OrderChannel? channel,
    String? tableId,
    bool clearTableId = false,
    String? tableSessionId,
    bool clearTableSessionId = false,
    List<CartItem>? lines,
    String? customerNote,
    String? kitchenNote,
    Discount? discount,
    bool clearDiscount = false,
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
      discount: clearDiscount ? null : (discount ?? this.discount),
      fees: fees ?? this.fees,
      tip: tip ?? this.tip,
      pricing: pricing ?? this.pricing,
    );
  }
}
