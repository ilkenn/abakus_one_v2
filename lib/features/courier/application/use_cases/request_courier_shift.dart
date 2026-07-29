import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../data/courier_shift_repository.dart';
import '../../domain/shift/courier_shift.dart';
import '../../domain/shift/courier_shift_status.dart';
import '../identity/courier_shift_id_generator.dart';

/// A courier requests a new shift — "courier may request shift start."
/// Created directly at [CourierShiftStatus.awaitingManagerApproval]
/// (skipping a separate pre-scheduling step, which no UI in this phase
/// requires — a deliberate simplification of the brief's full
/// `scheduled -> awaitingManagerApproval` chain, reported in
/// `docs/decisions.md` ADR-017).
///
/// Only one active (non-terminal) shift per courier is ever permitted —
/// throws [CourierShiftAlreadyActiveViolation] otherwise.
class RequestCourierShift {
  const RequestCourierShift({
    required Clock clock,
    required CourierShiftIdGenerator idGenerator,
    required CourierShiftRepository repository,
  })  : _clock = clock,
        _idGenerator = idGenerator,
        _repository = repository;

  final Clock _clock;
  final CourierShiftIdGenerator _idGenerator;
  final CourierShiftRepository _repository;

  Future<CourierShift> call({
    required String courierId,
    required String branchId,
  }) async {
    final existingActive = await _repository.findActiveByCourierId(courierId);
    if (existingActive != null) {
      throw CourierShiftAlreadyActiveViolation(courierId: courierId);
    }

    final shift = CourierShift(
      id: _idGenerator.nextShiftId(),
      courierId: courierId,
      branchId: branchId,
      status: CourierShiftStatus.awaitingManagerApproval,
      requestedAt: _clock.now(),
      revision: 1,
    );
    await _repository.save(shift);
    return shift;
  }
}
