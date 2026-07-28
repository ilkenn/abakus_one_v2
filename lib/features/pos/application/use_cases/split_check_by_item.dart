import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../../qr/data/table_session_repository.dart';
import '../../application/identity/check_id_generator.dart';
import '../../data/check_repository.dart';
import '../../data/pos_order_repository.dart';
import '../../domain/models/check.dart';
import '../../domain/models/check_status.dart';
import 'calculate_pos_order_totals.dart';
import 'start_pos_order.dart';

/// Splits a subset of [sourceCheckId]'s draft lines off into a brand-new
/// [Check] under the same [TableSession] — **pre-submission only** (the
/// source check must be [CheckStatus.open]).
///
/// Throws [CheckNotOpenViolation] if the source isn't open, or
/// [UnknownOrderLineDraftViolation] for any requested id not present in
/// its session.
class SplitCheckByItem {
  const SplitCheckByItem({
    required Clock clock,
    required CheckIdGenerator idGenerator,
    required CheckRepository checkRepository,
    required PosOrderRepository posOrderRepository,
    required TableSessionRepository tableSessionRepository,
  })  : _clock = clock,
        _idGenerator = idGenerator,
        _checkRepository = checkRepository,
        _posOrderRepository = posOrderRepository,
        _tableSessionRepository = tableSessionRepository,
        _calculateTotals = const CalculatePosOrderTotals();

  final Clock _clock;
  final CheckIdGenerator _idGenerator;
  final CheckRepository _checkRepository;
  final PosOrderRepository _posOrderRepository;
  final TableSessionRepository _tableSessionRepository;
  final CalculatePosOrderTotals _calculateTotals;

  Future<Check> call({
    required String sourceCheckId,
    required List<String> orderLineDraftIds,
    required String openedByStaffId,
  }) async {
    final source = await _checkRepository.findById(sourceCheckId);
    if (source == null) {
      throw UnknownRestaurantOperationsEntityViolation(
        entityName: 'Check',
        id: sourceCheckId,
      );
    }
    if (source.status != CheckStatus.open) {
      throw CheckNotOpenViolation(checkId: sourceCheckId);
    }

    final sourceSession =
        await _posOrderRepository.getDraft(source.posOrderSessionId!);
    if (sourceSession == null) {
      throw UnknownRestaurantOperationsEntityViolation(
        entityName: 'PosOrderSession',
        id: source.posOrderSessionId!,
      );
    }
    for (final id in orderLineDraftIds) {
      if (!sourceSession.lines.any((draft) => draft.id == id)) {
        throw UnknownOrderLineDraftViolation(orderLineDraftId: id);
      }
    }

    final now = _clock.now();
    final movedDrafts = [
      for (final draft in sourceSession.lines)
        if (orderLineDraftIds.contains(draft.id)) draft,
    ];

    final newCheckId = _idGenerator.nextCheckId();
    final newSession = StartPosOrder(clock: _clock)(
      sessionId: '$newCheckId-session',
      branchId: source.branchId,
      openedByStaffId: openedByStaffId,
      channel: sourceSession.channel,
      tableId: sourceSession.tableId,
      tableSessionId: sourceSession.tableSessionId,
    ).copyWith(lines: movedDrafts, lastUpdatedAt: now);
    await _posOrderRepository.saveDraft(
      newSession.sessionId,
      newSession.copyWith(pricing: _calculateTotals(newSession)),
    );

    final remainingSource = sourceSession.copyWith(
      lines: [
        for (final draft in sourceSession.lines)
          if (!orderLineDraftIds.contains(draft.id)) draft,
      ],
      lastUpdatedAt: now,
    );
    await _posOrderRepository.saveDraft(
      source.posOrderSessionId!,
      remainingSource.copyWith(pricing: _calculateTotals(remainingSource)),
    );

    final newCheck = Check(
      id: newCheckId,
      tableSessionId: source.tableSessionId,
      branchId: source.branchId,
      guestSessionIds: source.guestSessionIds,
      status: CheckStatus.open,
      posOrderSessionId: newSession.sessionId,
      openedAt: now,
      revision: 1,
    );
    await _checkRepository.save(newCheck);

    final tableSession =
        await _tableSessionRepository.findById(source.tableSessionId);
    if (tableSession != null) {
      await _tableSessionRepository
          .save(tableSession.withCheckAdded(newCheckId));
    }

    return newCheck;
  }
}
