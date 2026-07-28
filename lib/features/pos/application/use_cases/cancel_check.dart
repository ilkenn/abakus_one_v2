import '../../../../core/errors/business_rule_violation.dart';
import '../../data/check_repository.dart';
import '../../data/pos_order_repository.dart';
import '../../domain/models/check.dart';
import '../../domain/models/check_status.dart';

/// Cancels a still-open (pre-submission) [Check] and discards its
/// [PosOrderSession] draft — never valid once the check has been
/// submitted (see [CheckStatus.submitted]); use `VoidPayment`/refund flows
/// instead once a check has become a real `Order`.
///
/// Throws [CheckNotOpenViolation] if the check isn't
/// [CheckStatus.open].
class CancelCheck {
  const CancelCheck({
    required CheckRepository checkRepository,
    required PosOrderRepository posOrderRepository,
  })  : _checkRepository = checkRepository,
        _posOrderRepository = posOrderRepository;

  final CheckRepository _checkRepository;
  final PosOrderRepository _posOrderRepository;

  Future<Check> call(Check check) async {
    if (check.status != CheckStatus.open) {
      throw CheckNotOpenViolation(checkId: check.id);
    }

    if (check.posOrderSessionId != null) {
      await _posOrderRepository.deleteDraft(check.posOrderSessionId!);
    }

    final cancelled = check.copyWith(
      status: CheckStatus.cancelled,
      revision: check.revision + 1,
    );
    await _checkRepository.save(cancelled);
    return cancelled;
  }
}
