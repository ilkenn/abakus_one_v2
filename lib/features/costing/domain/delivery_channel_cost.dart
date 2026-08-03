import '../../../shared/models/money.dart';

/// A per-order cost attributable to a specific sales channel (a
/// marketplace commission, a delivery platform fee) — Phase 7
/// (`docs/decisions.md` ADR-024). [channelCode] is a free-text code
/// rather than importing `features/orders`' `OrderChannel` enum —
/// keeps `features/costing` from depending on the orders bounded
/// context for what is, this phase, purely reference configuration
/// (composed into profitability by 7N, same as [PackagingCost]).
class DeliveryChannelCost {
  const DeliveryChannelCost({
    required this.id,
    required this.organizationId,
    required this.channelCode,
    required this.costPerOrder,
    required this.createdAt,
  });

  final String id;
  final String organizationId;
  final String channelCode;
  final Money costPerOrder;
  final DateTime createdAt;
}
