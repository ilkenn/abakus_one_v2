import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../../pos/domain/authorization/real_pos_authorization_policy.dart';
import '../../data/stock_location_repository.dart';
import '../../domain/stock_location.dart';
import '../identity/stock_location_id_generator.dart';

/// Creates a [StockLocation] — manager+
/// (`PosAuthorizedAction.manageInventory`).
class CreateStockLocation {
  const CreateStockLocation({
    required PosAuthorizationPolicy authorizationPolicy,
    required StockLocationIdGenerator idGenerator,
    required StockLocationRepository repository,
  })  : _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _repository = repository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final StockLocationIdGenerator _idGenerator;
  final StockLocationRepository _repository;

  Future<StockLocation> call({
    required String branchId,
    required String name,
    required String performedByStaffId,
    required DateTime performedAt,
  }) async {
    const action = PosAuthorizedAction.manageInventory;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
      context: {kBranchIdAuthorizationContextKey: branchId},
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final location = StockLocation(
      id: _idGenerator.nextStockLocationId(),
      branchId: branchId,
      name: name,
      createdAt: performedAt,
      revision: 1,
    );
    await _repository.save(location);
    return location;
  }
}
