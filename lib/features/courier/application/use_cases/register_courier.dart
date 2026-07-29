import '../../data/courier_repository.dart';
import '../../domain/identity/courier.dart';
import '../../domain/identity/courier_registry_status.dart';
import '../../domain/identity/courier_vehicle_type.dart';
import '../identity/courier_id_generator.dart';

/// Registers a new [Courier] — "active/inactive courier registry."
/// Deliberately minimal contact data (name + phone only); no unnecessary
/// sensitive personal data is collected.
class RegisterCourier {
  const RegisterCourier({
    required CourierIdGenerator idGenerator,
    required CourierRepository repository,
  })  : _idGenerator = idGenerator,
        _repository = repository;

  final CourierIdGenerator _idGenerator;
  final CourierRepository _repository;

  Future<Courier> call({
    required String primaryBranchId,
    List<String> eligibleBranchIds = const [],
    required String displayName,
    required String phoneNumber,
    required CourierVehicleType vehicleType,
    String vehicleIdentifier = '',
    required int capacity,
    required DateTime registeredAt,
  }) async {
    final courier = Courier(
      id: _idGenerator.nextCourierId(),
      primaryBranchId: primaryBranchId,
      eligibleBranchIds: eligibleBranchIds,
      displayName: displayName,
      phoneNumber: phoneNumber,
      vehicleType: vehicleType,
      vehicleIdentifier: vehicleIdentifier,
      capacity: capacity,
      status: CourierRegistryStatus.active,
      registeredAt: registeredAt,
    );
    await _repository.save(courier);
    return courier;
  }
}
