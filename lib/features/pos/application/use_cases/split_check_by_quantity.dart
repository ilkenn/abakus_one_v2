import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../../qr/data/table_session_repository.dart';
import '../../application/identity/check_id_generator.dart';
import '../../application/identity/pos_order_line_draft_id_generator.dart';
import '../../data/check_repository.dart';
import '../../data/pos_order_repository.dart';
import '../../domain/models/check.dart';
import '../../domain/models/check_status.dart';
import '../../domain/models/pos_order_line_draft.dart';
import 'calculate_pos_order_totals.dart';
import 'start_pos_order.dart';

/// Splits [quantityToSplitOff] units off one draft line into a brand-new
/// [Check] under the same [TableSession] — the source line's quantity is
/// reduced by that amount; the new check gets a fresh line with exactly
/// that quantity. **Pre-submission only** (the source check must be
/// [CheckStatus.open]).
///
/// Throws [CheckNotOpenViolation] if the source isn't open,
/// [UnknownOrderLineDraftViolation] if [orderLineDraftId] isn't present,
/// or [NonPositiveQuantityViolation] if [quantityToSplitOff] is not
/// strictly less than the line's current quantity (splitting off the
/// entire quantity is `SplitCheckByItem`'s job, not this one's — it would
/// leave a zero-quantity line behind, which this codebase never
/// represents).
class SplitCheckByQuantity {
  const SplitCheckByQuantity({
    required Clock clock,
    required CheckIdGenerator checkIdGenerator,
    required PosOrderLineDraftIdGenerator draftIdGenerator,
    required CheckRepository checkRepository,
    required PosOrderRepository posOrderRepository,
    required TableSessionRepository tableSessionRepository,
  })  : _clock = clock,
        _checkIdGenerator = checkIdGenerator,
        _draftIdGenerator = draftIdGenerator,
        _checkRepository = checkRepository,
        _posOrderRepository = posOrderRepository,
        _tableSessionRepository = tableSessionRepository,
        _calculateTotals = const CalculatePosOrderTotals();

  final Clock _clock;
  final CheckIdGenerator _checkIdGenerator;
  final PosOrderLineDraftIdGenerator _draftIdGenerator;
  final CheckRepository _checkRepository;
  final PosOrderRepository _posOrderRepository;
  final TableSessionRepository _tableSessionRepository;
  final CalculatePosOrderTotals _calculateTotals;

  Future<Check> call({
    required String sourceCheckId,
    required String orderLineDraftId,
    required int quantityToSplitOff,
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
    PosOrderLineDraft? target;
    for (final draft in sourceSession.lines) {
      if (draft.id == orderLineDraftId) target = draft;
    }
    if (target == null) {
      throw UnknownOrderLineDraftViolation(orderLineDraftId: orderLineDraftId);
    }
    if (quantityToSplitOff <= 0 || quantityToSplitOff >= target.item.quantity) {
      throw NonPositiveQuantityViolation(
        context: 'SplitCheckByQuantity.quantityToSplitOff',
        quantity: quantityToSplitOff,
      );
    }

    final now = _clock.now();
    final remainingQuantity = target.item.quantity - quantityToSplitOff;
    final updatedSource = sourceSession.copyWith(
      lines: [
        for (final draft in sourceSession.lines)
          if (draft.id == orderLineDraftId)
            draft.copyWith(
                item: draft.item.copyWith(quantity: remainingQuantity))
          else
            draft,
      ],
      lastUpdatedAt: now,
    );
    await _posOrderRepository.saveDraft(
      source.posOrderSessionId!,
      updatedSource.copyWith(pricing: _calculateTotals(updatedSource)),
    );

    final splitDraft = PosOrderLineDraft(
      id: _draftIdGenerator.nextDraftId(),
      item: target.item.copyWith(quantity: quantityToSplitOff),
    );
    final newCheckId = _checkIdGenerator.nextCheckId();
    final newSession = StartPosOrder(clock: _clock)(
      sessionId: '$newCheckId-session',
      branchId: source.branchId,
      openedByStaffId: openedByStaffId,
      channel: sourceSession.channel,
      tableId: sourceSession.tableId,
      tableSessionId: sourceSession.tableSessionId,
    ).copyWith(lines: [splitDraft], lastUpdatedAt: now);
    await _posOrderRepository.saveDraft(
      newSession.sessionId,
      newSession.copyWith(pricing: _calculateTotals(newSession)),
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
