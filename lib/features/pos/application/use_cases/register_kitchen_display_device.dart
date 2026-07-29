import '../../data/kitchen_display_device_repository.dart';
import '../../domain/kds/kitchen_display_device.dart';
import '../../domain/kds/kitchen_station.dart';
import '../identity/kitchen_display_device_id_generator.dart';

/// Registers a new [KitchenDisplayDevice] for a branch — Phase 4G's
/// "device registration." The first `Device` concept of any kind in this
/// codebase (see `docs/decisions.md` ADR-016).
class RegisterKitchenDisplayDevice {
  const RegisterKitchenDisplayDevice({
    required KitchenDisplayDeviceIdGenerator idGenerator,
    required KitchenDisplayDeviceRepository repository,
  })  : _idGenerator = idGenerator,
        _repository = repository;

  final KitchenDisplayDeviceIdGenerator _idGenerator;
  final KitchenDisplayDeviceRepository _repository;

  Future<KitchenDisplayDevice> call({
    required String branchId,
    required String name,
    Set<KitchenStation>? stationScope,
    required DateTime registeredAt,
  }) async {
    final device = KitchenDisplayDevice(
      id: _idGenerator.nextDeviceId(),
      branchId: branchId,
      name: name,
      stationScope: stationScope,
      registeredAt: registeredAt,
    );
    await _repository.save(device);
    return device;
  }
}
