import '../../../orders/domain/models/order_channel.dart';
import '../../../orders/domain/models/order_status.dart';

/// The header block every printed/digital [KitchenTicket] must show.
class KitchenTicketHeader {
  const KitchenTicketHeader({
    required this.restaurantName,
    required this.branchName,
    required this.channelLabel,
    required this.orderNumber,
    required this.orderTypeLabel,
    required this.receivedAt,
    this.priority = '',
    this.tableLabel,
    this.customerName,
    this.channel = OrderChannel.delivery,
    this.orderStatus,
    this.orderNote = '',
  });

  /// 2026-11-08 — the canonical order's own current [OrderStatus], additive
  /// alongside [channel]. The KDS card's footer actions
  /// (Hazırlanıyor/Hazırlandı/Teslim Edildi/İptal Et) key off this — the
  /// backend's `advance*OrderStatus` callables accept only the EXACT next
  /// status, so the card must know where the order actually is rather than
  /// guess from its work items' line statuses (the two are tracked
  /// separately). `null` for a ticket not derived from a real order
  /// (in-memory/test tickets) — the card then shows no order-level actions.
  final OrderStatus? orderStatus;

  /// 2026-11-11 — the order-level kitchen note ("Et orta-iyi pişsin"),
  /// shown on the KDS card and printed on the kitchen ticket. Empty when
  /// the order has none.
  final String orderNote;

  final String restaurantName;
  final String branchName;

  /// Source platform/channel, human-readable (e.g. "Masa QR", "Gel-Al",
  /// "Getir Yemek") — display text, not the raw `OrderChannel` enum name.
  final String channelLabel;

  /// 2026-10-29 — the real, raw channel, additive alongside [channelLabel]
  /// (display text only). Needed so the KDS detail screen's whole-order
  /// cancel action knows which `advance*OrderStatus` callable actually
  /// accepts `targetStatus: 'cancelled'` for this specific ticket
  /// (`dineInQr` only, today — `dineInStaff`/`takeaway`/`delivery`/
  /// `reservationPreorder` each have their own separate cancellation
  /// mechanism, confirmed by reading `advanceDineInOrderStatus.ts`'s own
  /// explicit `order.channel !== "dineInQr"` check). Defaults to
  /// [OrderChannel.delivery] only so the many existing tests that
  /// construct this class directly, pre-dating this field, don't all need
  /// updating — every real ticket (`KitchenTicketMapper.fromOrder`) always
  /// supplies the order's own real channel explicitly.
  final OrderChannel channel;

  final String orderNumber;

  /// Dine-in / takeaway / delivery / reservation — display text.
  final String orderTypeLabel;

  final DateTime receivedAt;

  /// Free-text priority marker (e.g. "ACİL") — empty for normal priority,
  /// not modeled as an enum since kitchens define their own urgency
  /// vocabulary.
  final String priority;

  /// AP-5 Sprint 4 — display-only table reference (e.g. "Masa 5"), derived
  /// from `Order.tableId`. `null` for channels with no table (takeaway/
  /// delivery/reservation-preorder). Additive beyond BR-KITCHEN-006's
  /// locked required-field list (which names a floor, not a ceiling) —
  /// never removes/replaces any of that rule's own required fields.
  final String? tableLabel;

  /// AP-5 Sprint 4 — display-only customer name, derived from
  /// `Order.contactFirstName`/`contactLastName`. `null` when the order
  /// carries no contact name. Same additive-beyond-BR-KITCHEN-006 note as
  /// [tableLabel].
  final String? customerName;
}
