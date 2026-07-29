import '../domain/device/courier_device.dart';

/// Storage for [CourierDevice] records — mutable registry, mirrors
/// `KitchenDisplayDeviceRepository`.
abstract interface class CourierDeviceRepository {
  Future<void> save(CourierDevice device);
  Future<CourierDevice?> findById(String deviceId);
  Future<List<CourierDevice>> findByCourierId(String courierId);
}

class InMemoryCourierDeviceRepository implements CourierDeviceRepository {
  final Map<String, CourierDevice> _byId = {};

  @override
  Future<void> save(CourierDevice device) async => _byId[device.id] = device;

  @override
  Future<CourierDevice?> findById(String deviceId) async => _byId[deviceId];

  @override
  Future<List<CourierDevice>> findByCourierId(String courierId) async {
    return List.unmodifiable(
      _byId.values.where((d) => d.courierId == courierId),
    );
  }
}
