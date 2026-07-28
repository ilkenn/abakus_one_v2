import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../../qr/data/table_session_repository.dart';
import '../../../qr/domain/models/table_session.dart';
import '../../data/check_repository.dart';
import '../../data/order_closure_repository.dart';
import '../../domain/models/check.dart';
import '../../domain/models/check_status.dart';
import '../../domain/models/order_closure_lifecycle_status.dart';

/// Closes a [TableSession] — only once every [Check] opened under it is
/// resolved: `cancelled`, or `submitted` **and** that check's own
/// `Order`'s [OrderClosure] has reached
/// [OrderClosureLifecycleStatus.closed]. Never checks payment/closure
/// state itself beyond reading it — `CloseTableSession` does not duplicate
/// or reimplement `OrderClosure`'s own lifecycle (Phase 3 Sprint 3C).
///
/// Throws [TableSessionNotReadyToCloseViolation] listing how many checks
/// are still unresolved. Throws
/// [UnknownRestaurantOperationsEntityViolation] if [tableSessionId]
/// doesn't resolve.
class CloseTableSession {
  const CloseTableSession({
    required Clock clock,
    required TableSessionRepository tableSessionRepository,
    required CheckRepository checkRepository,
    required OrderClosureRepository orderClosureRepository,
  })  : _clock = clock,
        _tableSessionRepository = tableSessionRepository,
        _checkRepository = checkRepository,
        _orderClosureRepository = orderClosureRepository;

  final Clock _clock;
  final TableSessionRepository _tableSessionRepository;
  final CheckRepository _checkRepository;
  final OrderClosureRepository _orderClosureRepository;

  Future<TableSession> call(String tableSessionId) async {
    final tableSession = await _tableSessionRepository.findById(tableSessionId);
    if (tableSession == null) {
      throw UnknownRestaurantOperationsEntityViolation(
        entityName: 'TableSession',
        id: tableSessionId,
      );
    }

    final checks = await _checkRepository.findByTableSessionId(tableSessionId);
    var unresolvedCount = 0;
    for (final check in checks) {
      if (!await _isResolved(check)) unresolvedCount += 1;
    }
    if (unresolvedCount > 0) {
      throw TableSessionNotReadyToCloseViolation(
        unresolvedCheckCount: unresolvedCount,
      );
    }

    final closed = tableSession.closed(at: _clock.now());
    await _tableSessionRepository.save(closed);
    return closed;
  }

  Future<bool> _isResolved(Check check) async {
    if (check.status == CheckStatus.cancelled) return true;
    if (check.status != CheckStatus.submitted || check.orderId == null) {
      return false;
    }
    final closure =
        await _orderClosureRepository.findCurrentByOrderId(check.orderId!);
    return closure?.lifecycleStatus == OrderClosureLifecycleStatus.closed;
  }
}
