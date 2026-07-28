import '../../../../core/errors/business_rule_violation.dart';
import '../../../orders/data/package_preparation_repository.dart';
import '../../../orders/domain/fulfillment/package_preparation.dart';
import '../../../orders/domain/fulfillment/package_preparation_status.dart';
import '../../../orders/domain/models/order_id.dart';

/// Moves [orderId]'s current [PackagePreparation] to [newStatus].
///
/// Reaching [PackagePreparationStatus.packed] records [performedByStaffId]
/// as [PackagePreparation.preparedByStaffId] and [at] as
/// [PackagePreparation.preparationCompletedAt] — the "preparer identity"
/// and "completion timestamp" the packaging checklist requires. Quality
/// control is a separate step (`CompleteQualityControl`), not folded in
/// here.
///
/// Throws [UnknownRestaurantOperationsEntityViolation] if no
/// [PackagePreparation] exists yet, or
/// [InvalidPackagePreparationTransitionViolation] if
/// [PackagePreparationTransitions.canTransition] rejects the move.
class AdvancePackagePreparation {
  const AdvancePackagePreparation({
    required PackagePreparationRepository repository,
  }) : _repository = repository;

  final PackagePreparationRepository _repository;

  Future<PackagePreparation> call({
    required OrderId orderId,
    required PackagePreparationStatus newStatus,
    required String performedByStaffId,
    required DateTime at,
  }) async {
    final current = await _repository.findCurrentByOrderId(orderId);
    if (current == null) {
      throw UnknownRestaurantOperationsEntityViolation(
        entityName: 'PackagePreparation',
        id: orderId.value,
      );
    }
    if (!PackagePreparationTransitions.canTransition(
        current.status, newStatus)) {
      throw InvalidPackagePreparationTransitionViolation(
        fromStatusName: current.status.name,
        toStatusName: newStatus.name,
      );
    }

    final updated = current.copyWith(
      status: newStatus,
      revision: current.revision + 1,
      preparedByStaffId: newStatus == PackagePreparationStatus.packed
          ? performedByStaffId
          : null,
      preparationCompletedAt:
          newStatus == PackagePreparationStatus.packed ? at : null,
    );
    await _repository.save(updated);
    return updated;
  }
}
