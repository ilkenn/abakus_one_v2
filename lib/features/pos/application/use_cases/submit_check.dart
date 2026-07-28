import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../../orders/domain/identity/order_identity.dart';
import '../../../orders/domain/models/order.dart';
import '../../../qr/data/table_session_repository.dart';
import '../../data/check_repository.dart';
import '../../data/pos_order_repository.dart';
import '../../domain/models/check.dart';
import '../../domain/models/check_status.dart';
import 'submit_pos_order.dart';

/// Submits an open [Check]'s [PosOrderSession] into a real [Order] —
/// thin orchestration over the existing, unchanged `SubmitPosOrder`
/// (Phase 3 Sprint 3B/3C). Never duplicates its validation, identity, or
/// persistence logic.
///
/// Throws [CheckNotOpenViolation] if the check has already been submitted
/// or cancelled. Any [BusinessRuleViolation] `SubmitPosOrder` itself
/// throws (e.g. [EmptyOrderViolation]) propagates unchanged.
class SubmitCheck {
  const SubmitCheck({
    required Clock clock,
    required OrderIdentityProvider identityProvider,
    required String restaurantId,
    required CheckRepository checkRepository,
    required PosOrderRepository posOrderRepository,
    required TableSessionRepository tableSessionRepository,
  })  : _clock = clock,
        _identityProvider = identityProvider,
        _restaurantId = restaurantId,
        _checkRepository = checkRepository,
        _posOrderRepository = posOrderRepository,
        _tableSessionRepository = tableSessionRepository;

  final Clock _clock;
  final OrderIdentityProvider _identityProvider;
  final String _restaurantId;
  final CheckRepository _checkRepository;
  final PosOrderRepository _posOrderRepository;
  final TableSessionRepository _tableSessionRepository;

  Future<Order> call(Check check) async {
    if (check.status != CheckStatus.open) {
      throw CheckNotOpenViolation(checkId: check.id);
    }

    final session = await _posOrderRepository.getDraft(
      check.posOrderSessionId!,
    );
    if (session == null) {
      throw UnknownRestaurantOperationsEntityViolation(
        entityName: 'PosOrderSession',
        id: check.posOrderSessionId!,
      );
    }

    final order = await SubmitPosOrder(
      clock: _clock,
      identityProvider: _identityProvider,
      repository: _posOrderRepository,
      restaurantId: _restaurantId,
    ).call(session);

    await _checkRepository.save(
      check.copyWith(
        status: CheckStatus.submitted,
        orderId: order.id,
        revision: check.revision + 1,
      ),
    );

    final tableSession =
        await _tableSessionRepository.findById(check.tableSessionId);
    if (tableSession != null) {
      await _tableSessionRepository
          .save(tableSession.withOrderAdded(order.id.value));
    }

    return order;
  }
}
