import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../../orders/domain/models/order_channel.dart';
import '../../../qr/data/table_session_repository.dart';
import '../../data/check_repository.dart';
import '../../data/pos_order_repository.dart';
import '../identity/check_id_generator.dart';
import '../../domain/models/check.dart';
import '../../domain/models/check_status.dart';
import 'start_pos_order.dart';

/// Opens a new [Check] under an existing, active [TableSession] — starts
/// its own [PosOrderSession] via [StartPosOrder] and links the two
/// (`Check.posOrderSessionId`), then appends the new check id onto the
/// table session (`TableSession.withCheckAdded`).
///
/// Throws [UnknownRestaurantOperationsEntityViolation] if
/// [tableSessionId] doesn't resolve to a `TableSession`.
class OpenCheck {
  const OpenCheck({
    required Clock clock,
    required CheckIdGenerator idGenerator,
    required TableSessionRepository tableSessionRepository,
    required PosOrderRepository posOrderRepository,
    required CheckRepository checkRepository,
  })  : _clock = clock,
        _idGenerator = idGenerator,
        _tableSessionRepository = tableSessionRepository,
        _posOrderRepository = posOrderRepository,
        _checkRepository = checkRepository;

  final Clock _clock;
  final CheckIdGenerator _idGenerator;
  final TableSessionRepository _tableSessionRepository;
  final PosOrderRepository _posOrderRepository;
  final CheckRepository _checkRepository;

  Future<Check> call({
    required String tableSessionId,
    required String openedByStaffId,
    OrderChannel channel = OrderChannel.dineInStaff,
  }) async {
    final tableSession = await _tableSessionRepository.findById(tableSessionId);
    if (tableSession == null) {
      throw UnknownRestaurantOperationsEntityViolation(
        entityName: 'TableSession',
        id: tableSessionId,
      );
    }

    final checkId = _idGenerator.nextCheckId();
    final now = _clock.now();

    final session = StartPosOrder(clock: _clock)(
      sessionId: '$checkId-session',
      branchId: tableSession.branchId,
      openedByStaffId: openedByStaffId,
      channel: channel,
      tableId: tableSession.tableId,
      tableSessionId: tableSessionId,
    );
    await _posOrderRepository.saveDraft(session.sessionId, session);

    final check = Check(
      id: checkId,
      tableSessionId: tableSessionId,
      branchId: tableSession.branchId,
      status: CheckStatus.open,
      posOrderSessionId: session.sessionId,
      openedAt: now,
      revision: 1,
    );

    await _checkRepository.save(check);
    await _tableSessionRepository.save(tableSession.withCheckAdded(checkId));

    return check;
  }
}
