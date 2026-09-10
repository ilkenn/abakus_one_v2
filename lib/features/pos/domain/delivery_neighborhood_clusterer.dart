import '../../orders/domain/models/order.dart';

/// AP-6 Sprint 3 — one neighborhood's group of orders for the dispatch
/// console's "Fulya Bölgesi (3 Paket)"-style cluster card.
/// [neighborhoodName] is `null` for the ungrouped bucket (orders whose
/// [Order.deliveryAddressSnapshot] has no `neighborhoodName` — the address
/// provider didn't resolve one) — these are never silently dropped, just
/// never clustered.
class NeighborhoodCluster {
  const NeighborhoodCluster({required this.neighborhoodName, required this.orders});

  final String? neighborhoodName;
  final List<Order> orders;
}

/// A pure, stateless grouping of delivery orders by
/// `Order.deliveryAddressSnapshot?.neighborhoodName` — the field already
/// exists on every order's address snapshot (provider-sourced, e.g. Google
/// Places); this sprint adds no new address field, only this grouping
/// engine. Mirrors `CourierReturnFifo`'s own plain-static-function shape.
abstract final class DeliveryNeighborhoodClusterer {
  DeliveryNeighborhoodClusterer._();

  /// Groups [orders] by neighborhood name, largest cluster first (ties
  /// broken alphabetically by neighborhood name, so repeated calls against
  /// the same input are always deterministic); the ungrouped (`null`
  /// neighborhood) bucket, if non-empty, always sorts last regardless of
  /// its size — it's a fallback, never a "region," so it should never
  /// visually outrank a real neighborhood card.
  static List<NeighborhoodCluster> cluster(List<Order> orders) {
    final byNeighborhood = <String?, List<Order>>{};
    for (final order in orders) {
      final neighborhoodName = order.deliveryAddressSnapshot?.neighborhoodName;
      byNeighborhood.putIfAbsent(neighborhoodName, () => []).add(order);
    }

    final named = byNeighborhood.entries.where((e) => e.key != null).toList()
      ..sort((a, b) {
        final byCount = b.value.length.compareTo(a.value.length);
        if (byCount != 0) return byCount;
        return a.key!.compareTo(b.key!);
      });

    final ungrouped = byNeighborhood[null];

    return [
      for (final entry in named)
        NeighborhoodCluster(neighborhoodName: entry.key, orders: entry.value),
      if (ungrouped != null && ungrouped.isNotEmpty)
        NeighborhoodCluster(neighborhoodName: null, orders: ungrouped),
    ];
  }
}
