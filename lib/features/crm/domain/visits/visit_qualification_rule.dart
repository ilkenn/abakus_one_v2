import '../../../orders/domain/models/order_channel.dart';
import '../../../orders/domain/models/order_status.dart';

/// Pure, side-effect-free rule for "does this order qualify for automatic
/// customer visit recording" — **Sprint 5E Part 5**
/// (`docs/decisions.md` ADR-022), extracted so the qualification logic is
/// documented and directly testable independent of whether any live
/// trigger actually calls it yet.
///
/// **The gate is completion status, not channel.** Every [OrderChannel]
/// value qualifies once the order reaches [OrderStatus.completed] — a
/// customer's visit to the restaurant is the same real-world event
/// regardless of whether they ordered by QR table, staff-entered dine-in,
/// takeaway, delivery, or a reservation preorder. [channel] is still an
/// explicit parameter (not dropped) so a future business decision to
/// exclude a specific channel (e.g. an internal test/comp order channel,
/// if one is ever added) has one single, obvious place to encode that
/// exclusion — today, none exists.
///
/// **Honest limitation** (see `docs/feature_status.md`'s Phase 5 Closure
/// Record): no real use case anywhere in this codebase transitions any
/// order to [OrderStatus.completed] today — only `LocalOrdersRepository`'s
/// hardcoded demo seed data does. This rule is therefore live-wired for
/// exactly one channel this sprint: `CompleteDelivery` treats reaching
/// [DeliveryStatus.delivered] (the real, live completion signal for the
/// delivery channel) as equivalent to "this delivery-channel order is
/// complete," rather than literally checking [OrderStatus.completed] on
/// the `Order` aggregate (which would make the wiring permanently
/// unreachable). Dine-in/takeaway/reservation-preorder channels have no
/// live trigger yet, since no real order-completion use case exists for
/// them to hook into — this rule still documents and tests how they
/// *would* qualify, so the moment that trigger exists, the rule itself
/// needs no changes.
abstract final class VisitQualificationRule {
  VisitQualificationRule._();

  static bool qualifies({
    required OrderChannel channel,
    required OrderStatus status,
  }) {
    return status == OrderStatus.completed;
  }
}
