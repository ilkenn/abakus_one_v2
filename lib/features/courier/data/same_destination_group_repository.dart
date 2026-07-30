import '../domain/delivery/same_destination_group.dart';

/// Append-only storage for [SameDestinationGroup] — Sprint 5C.
abstract interface class SameDestinationGroupRepository {
  Future<void> append(SameDestinationGroup group);

  /// The group containing [deliveryId], if any — a delivery belongs to at
  /// most one group.
  Future<SameDestinationGroup?> findByDeliveryId(String deliveryId);
}

class InMemorySameDestinationGroupRepository
    implements SameDestinationGroupRepository {
  final List<SameDestinationGroup> _groups = [];

  @override
  Future<void> append(SameDestinationGroup group) async {
    _groups.add(group);
  }

  @override
  Future<SameDestinationGroup?> findByDeliveryId(String deliveryId) async {
    for (final group in _groups) {
      if (group.deliveryIds.contains(deliveryId)) return group;
    }
    return null;
  }
}
