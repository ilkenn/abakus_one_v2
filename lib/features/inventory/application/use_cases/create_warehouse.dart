import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/warehouse_repository.dart';
import '../../domain/warehouse.dart';
import '../identity/warehouse_id_generator.dart';

/// Creates a [Warehouse] — manager+
/// (`PosAuthorizedAction.manageInventory`).
class CreateWarehouse {
  const CreateWarehouse({
    required PosAuthorizationPolicy authorizationPolicy,
    required WarehouseIdGenerator idGenerator,
    required WarehouseRepository repository,
  })  : _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _repository = repository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final WarehouseIdGenerator _idGenerator;
  final WarehouseRepository _repository;

  Future<Warehouse> call({
    required String restaurantId,
    required String name,
    required String performedByStaffId,
    required DateTime performedAt,
  }) async {
    const action = PosAuthorizedAction.manageInventory;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final warehouse = Warehouse(
      id: _idGenerator.nextWarehouseId(),
      restaurantId: restaurantId,
      name: name,
      createdAt: performedAt,
      revision: 1,
    );
    await _repository.save(warehouse);
    return warehouse;
  }
}
