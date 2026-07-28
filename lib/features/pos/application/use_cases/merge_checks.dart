import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../data/check_repository.dart';
import '../../data/pos_order_repository.dart';
import '../../domain/models/check.dart';
import '../../domain/models/check_status.dart';
import 'calculate_pos_order_totals.dart';

/// Merges [sourceCheckId]'s lines into [targetCheckId]'s draft session,
/// then cancels the source check — **pre-submission only** (both checks
/// must be [CheckStatus.open]), same scope boundary as
/// `TransferOrderLineDraft`.
///
/// Throws [CheckNotOpenViolation] naming whichever check isn't open.
class MergeChecks {
  const MergeChecks({
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

  Future<Check> call({
    required String sourceCheckId,
    required String targetCheckId,
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

    final now = _clock.now();
    final mergedTarget = targetSession.copyWith(
      lines: [...targetSession.lines, ...sourceSession.lines],
      lastUpdatedAt: now,
    );
    await _posOrderRepository.saveDraft(
      target.posOrderSessionId!,
      mergedTarget.copyWith(pricing: _calculateTotals(mergedTarget)),
    );
    await _posOrderRepository.deleteDraft(source.posOrderSessionId!);

    final cancelledSource = source.copyWith(
      status: CheckStatus.cancelled,
      revision: source.revision + 1,
    );
    await _checkRepository.save(cancelledSource);

    return cancelledSource;
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
