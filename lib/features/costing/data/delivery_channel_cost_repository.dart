import '../domain/delivery_channel_cost.dart';

abstract interface class DeliveryChannelCostRepository {
  Future<void> save(DeliveryChannelCost cost);
  Future<DeliveryChannelCost?> findByChannelCode(String channelCode);
  Future<List<DeliveryChannelCost>> findByOrganizationId(String organizationId);
}

class InMemoryDeliveryChannelCostRepository
    implements DeliveryChannelCostRepository {
  final Map<String, DeliveryChannelCost> _byId = {};

  @override
  Future<void> save(DeliveryChannelCost cost) async => _byId[cost.id] = cost;

  @override
  Future<DeliveryChannelCost?> findByChannelCode(String channelCode) async {
    for (final cost in _byId.values) {
      if (cost.channelCode == channelCode) return cost;
    }
    return null;
  }

  @override
  Future<List<DeliveryChannelCost>> findByOrganizationId(
      String organizationId) async {
    return List.unmodifiable(
      _byId.values.where((c) => c.organizationId == organizationId),
    );
  }
}
