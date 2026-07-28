import '../../../../core/errors/business_rule_violation.dart';
import '../../../orders/data/package_preparation_repository.dart';
import '../../../orders/domain/fulfillment/package_preparation.dart';
import '../../../orders/domain/models/order_id.dart';

/// Toggles one checklist item (matched by category + description) on
/// [orderId]'s current [PackagePreparation] and persists the new revision.
///
/// Throws [UnknownRestaurantOperationsEntityViolation] if no
/// [PackagePreparation] exists yet for [orderId] (`StartPackagePreparation`
/// must run first).
class UpdatePackageChecklist {
  const UpdatePackageChecklist({
    required PackagePreparationRepository repository,
  }) : _repository = repository;

  final PackagePreparationRepository _repository;

  Future<PackagePreparation> call({
    required OrderId orderId,
    required int checklistIndex,
    required bool isChecked,
  }) async {
    final current = await _repository.findCurrentByOrderId(orderId);
    if (current == null) {
      throw UnknownRestaurantOperationsEntityViolation(
        entityName: 'PackagePreparation',
        id: orderId.value,
      );
    }

    final updatedChecklist = [
      for (var i = 0; i < current.checklist.length; i++)
        if (i == checklistIndex)
          current.checklist[i].copyWith(isChecked: isChecked)
        else
          current.checklist[i],
    ];

    final updated = current.copyWith(
      checklist: updatedChecklist,
      revision: current.revision + 1,
    );
    await _repository.save(updated);
    return updated;
  }
}
