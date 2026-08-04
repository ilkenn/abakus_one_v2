import 'marketplace_order_mapping_status.dart';

/// Links an incoming marketplace order to this app's own internal
/// `Order` (`features/orders`) once created — Phase 8
/// (`docs/decisions.md` ADR-025), "Virtual Restaurant → Order
/// Mapping," the "Marketplace Mapping Engine"'s order leaf.
/// [internalOrderId] is `null` until mapping completes — a real order-
/// ingestion pipeline (Webhook Foundation, 8L) would receive the raw
/// marketplace order first and only create the internal `Order`
/// afterward; this record's own [status] tracks exactly that gap.
class MarketplaceOrderMapping {
  const MarketplaceOrderMapping({
    required this.id,
    required this.virtualRestaurantId,
    required this.externalOrderId,
    this.internalOrderId,
    this.status = MarketplaceOrderMappingStatus.received,
    required this.receivedAt,
    required this.revision,
  });

  final String id;
  final String virtualRestaurantId;

  /// The marketplace's own opaque order identifier.
  final String externalOrderId;

  final String? internalOrderId;
  final MarketplaceOrderMappingStatus status;
  final DateTime receivedAt;
  final int revision;

  MarketplaceOrderMapping copyWith({
    String? internalOrderId,
    MarketplaceOrderMappingStatus? status,
    required int revision,
  }) {
    return MarketplaceOrderMapping(
      id: id,
      virtualRestaurantId: virtualRestaurantId,
      externalOrderId: externalOrderId,
      internalOrderId: internalOrderId ?? this.internalOrderId,
      status: status ?? this.status,
      receivedAt: receivedAt,
      revision: revision,
    );
  }
}
