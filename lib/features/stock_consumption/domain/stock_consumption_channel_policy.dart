import 'stock_consumption_timing_policy.dart';

/// A branch's configured [StockConsumptionTimingPolicy] for one sales
/// channel — Phase 7 (`docs/decisions.md` ADR-024). [channelCode] is
/// free-text rather than importing `features/orders`' `OrderChannel`
/// enum — keeps `features/stock_consumption` from depending on the
/// orders bounded context for reference configuration (same choice
/// `DeliveryChannelCost`, 7M, already made). One policy per
/// branch+channel, upserted.
class StockConsumptionChannelPolicy {
  const StockConsumptionChannelPolicy({
    required this.id,
    required this.organizationId,
    required this.branchId,
    required this.channelCode,
    required this.timingPolicy,
    required this.createdAt,
    required this.revision,
  });

  final String id;
  final String organizationId;
  final String branchId;
  final String channelCode;
  final StockConsumptionTimingPolicy timingPolicy;
  final DateTime createdAt;
  final int revision;
}
