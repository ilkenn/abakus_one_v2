import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../data/check_repository.dart';
import '../../data/pos_order_repository.dart';
import '../../domain/models/check.dart';
import '../../domain/models/check_status.dart';
import 'calculate_pos_order_totals.dart';

/// Moves one [PosOrderLineDraft] (identified by its stable id) from one
/// still-open [Check]'s draft session to another — item-level split/
/// transfer, **pre-submission only** (Phase 3 Sprint 3D scope; see
/// `docs/decisions.md` ADR-013 for why post-submission item-level
/// correction is deferred: `OrderLine` has no stable id yet).
///
/// Both checks must be [CheckStatus.open] — throws [CheckNotOpenViolation]
/// naming whichever one isn't. Throws [UnknownOrderLineDraftViolation] if
/// [orderLineDraftId] isn't a line in the source check's session.
class TransferOrderLineDraft {
  const TransferOrderLineDraft({
    required Clock clock,
    required CheckRepository checkRepository,
    required PosOrderRepository posOrderRepository,
  })  : _clock = clock,
        _checkRepository = checkRepository,
        _posOrderRepository = posOrderRepository,
        _calculateTotals = const CalculatePosOrderTotals();

  final Clock _clock;
  final CheckRepository _checkRepository;
  final PosOrderRepository _posOrderRepository;
  final CalculatePosOrderTotals _calculateTotals;

  Future<void> call({
    required String sourceCheckId,
    required String targetCheckId,
    required String orderLineDraftId,
  }) async {
    final source = await _requireOpenCheck(sourceCheckId);
    final target = await _requireOpenCheck(targetCheckId);

    final sourceSession =
        await _posOrderRepository.getDraft(source.posOrderSessionId!);
    final targetSession =
        await _posOrderRepository.getDraft(target.posOrderSessionId!);
    if (sourceSession == null || targetSession == null) {
      throw UnknownRestaurantOperationsEntityViolation(
        entityName: 'PosOrderSession',
        id: sourceSession == null
            ? source.posOrderSessionId!
            : target.posOrderSessionId!,
      );
    }

    if (!sourceSession.lines.any((draft) => draft.id == orderLineDraftId)) {
      throw UnknownOrderLineDraftViolation(orderLineDraftId: orderLineDraftId);
    }
    final movedDraft =
        sourceSession.lines.firstWhere((draft) => draft.id == orderLineDraftId);

    final now = _clock.now();
    final updatedSource = sourceSession.copyWith(
      lines: [
        for (final draft in sourceSession.lines)
          if (draft.id != orderLineDraftId) draft,
      ],
      lastUpdatedAt: now,
    );
    final updatedTarget = targetSession.copyWith(
      lines: [...targetSession.lines, movedDraft],
      lastUpdatedAt: now,
    );

    await _posOrderRepository.saveDraft(
      source.posOrderSessionId!,
      updatedSource.copyWith(pricing: _calculateTotals(updatedSource)),
    );
    await _posOrderRepository.saveDraft(
      target.posOrderSessionId!,
      updatedTarget.copyWith(pricing: _calculateTotals(updatedTarget)),
    );
  }

  Future<Check> _requireOpenCheck(String checkId) async {
    final check = await _checkRepository.findById(checkId);
    if (check == null) {
      throw UnknownRestaurantOperationsEntityViolation(
        entityName: 'Check',
        id: checkId,
      );
    }
    if (check.status != CheckStatus.open) {
      throw CheckNotOpenViolation(checkId: checkId);
    }
    return check;
  }
}
