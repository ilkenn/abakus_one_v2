import '../domain/kds/kitchen_display_device.dart';

/// Storage for [KitchenDisplayDevice] records — mutable, mirrors
/// `CashDrawerRepository`'s shape: a device's current registry shape is
/// what matters, not a revision history of it.
abstract interface class KitchenDisplayDeviceRepository {
  Future<void> save(KitchenDisplayDevice device);

  Future<KitchenDisplayDevice?> findById(String deviceId);

  /// Branch data must never leak across branches — every query on this
  /// repository is branch-scoped, no unscoped "all devices" query exists.
  Future<List<KitchenDisplayDevice>> findByBranchId(String branchId);
}

/// In-memory [KitchenDisplayDeviceRepository] — the only implementation
/// this phase.
class InMemoryKitchenDisplayDeviceRepository
    implements KitchenDisplayDeviceRepository {
  final Map<String, KitchenDisplayDevice> _devicesById = {};

  @override
  Future<void> save(KitchenDisplayDevice device) async {
    _devicesById[device.id] = device;
  }

  @override
  Future<KitchenDisplayDevice?> findById(String deviceId) async {
    return _devicesById[deviceId];
  }

  @override
  Future<List<KitchenDisplayDevice>> findByBranchId(String branchId) async {
    return List.unmodifiable(
      _devicesById.values.where((d) => d.branchId == branchId),
    );
  }
}
