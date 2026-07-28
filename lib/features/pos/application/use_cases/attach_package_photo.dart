import '../../../../core/errors/business_rule_violation.dart';
import '../../../orders/data/package_preparation_repository.dart';
import '../../../orders/domain/fulfillment/package_preparation.dart';
import '../../../orders/domain/models/order_id.dart';

/// Attaches an optional package photograph's local asset/file path to
/// [orderId]'s current [PackagePreparation]. No upload/cloud-storage
/// integration exists this sprint — [assetPath] is expected to already be
/// a locally-captured file; this use case only records the reference.
///
/// Throws [UnknownRestaurantOperationsEntityViolation] if no
/// [PackagePreparation] exists yet.
class AttachPackagePhoto {
  const AttachPackagePhoto({
    required PackagePreparationRepository repository,
  }) : _repository = repository;

  final PackagePreparationRepository _repository;

  Future<PackagePreparation> call({
    required OrderId orderId,
    required String assetPath,
  }) async {
    final current = await _repository.findCurrentByOrderId(orderId);
    if (current == null) {
      throw UnknownRestaurantOperationsEntityViolation(
        entityName: 'PackagePreparation',
        id: orderId.value,
      );
    }
    final updated = current.copyWith(
      photoAssetPath: assetPath,
      revision: current.revision + 1,
    );
    await _repository.save(updated);
    return updated;
  }
}
