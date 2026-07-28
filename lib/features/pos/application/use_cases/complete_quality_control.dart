import '../../../../core/errors/business_rule_violation.dart';
import '../../../orders/data/package_preparation_repository.dart';
import '../../../orders/domain/fulfillment/package_preparation.dart';
import '../../../orders/domain/fulfillment/package_preparation_status.dart';
import '../../../orders/domain/models/order_id.dart';

/// Records a quality-control pass on an already-[PackagePreparationStatus.
/// packed] package — a separate identity/timestamp from
/// [PackagePreparation.preparedByStaffId] (`AdvancePackagePreparation`
/// sets that one), per the explicit requirement that the checklist track
/// preparer and quality-controller identity independently. Does not
/// change [PackagePreparation.status] itself — quality control is a
/// review of an already-completed pack, not a lifecycle stage of its own.
///
/// Throws [UnknownRestaurantOperationsEntityViolation] if no
/// [PackagePreparation] exists yet, or
/// [InvalidPackagePreparationTransitionViolation] if the package isn't
/// yet [PackagePreparationStatus.packed] (nothing to quality-control).
class CompleteQualityControl {
  const CompleteQualityControl({
    required PackagePreparationRepository repository,
  }) : _repository = repository;

  final PackagePreparationRepository _repository;

  Future<PackagePreparation> call({
    required OrderId orderId,
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
    if (current.status != PackagePreparationStatus.packed) {
      throw InvalidPackagePreparationTransitionViolation(
        fromStatusName: current.status.name,
        toStatusName: 'qualityControlled',
      );
    }

    final updated = current.copyWith(
      qualityControlledByStaffId: performedByStaffId,
      qualityControlCompletedAt: at,
      revision: current.revision + 1,
    );
    await _repository.save(updated);
    return updated;
  }
}
