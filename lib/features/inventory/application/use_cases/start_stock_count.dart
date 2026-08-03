import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../../pos/domain/authorization/real_pos_authorization_policy.dart';
import '../../data/stock_count_repository.dart';
import '../../domain/stock_count.dart';
import '../identity/stock_count_id_generator.dart';

/// Begins a new [StockCount] session at a [StockLocation] — staff+
/// (`PosAuthorizedAction.recordStockCount`), Phase 7
/// (`docs/decisions.md` ADR-024). Always a brand-new record — "a
/// mistaken count is corrected by starting a new `StockCount`," never
/// by reopening one already submitted.
class StartStockCount {
  const StartStockCount({
    required PosAuthorizationPolicy authorizationPolicy,
    required StockCountIdGenerator idGenerator,
    required StockCountRepository repository,
  })  : _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _repository = repository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final StockCountIdGenerator _idGenerator;
  final StockCountRepository _repository;

  Future<StockCount> call({
    required String branchId,
    required String locationId,
    required String performedByStaffId,
    required DateTime performedAt,
  }) async {
    const action = PosAuthorizedAction.recordStockCount;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
      context: {kBranchIdAuthorizationContextKey: branchId},
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final count = StockCount(
      id: _idGenerator.nextStockCountId(),
      branchId: branchId,
      locationId: locationId,
      startedByStaffId: performedByStaffId,
      startedAt: performedAt,
    );
    await _repository.save(count);
    return count;
  }
}
