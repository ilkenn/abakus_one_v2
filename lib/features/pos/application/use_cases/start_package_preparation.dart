import '../../../orders/data/package_preparation_repository.dart';
import '../../../orders/domain/fulfillment/package_checklist_item.dart';
import '../../../orders/domain/fulfillment/package_preparation.dart';
import '../../../orders/domain/fulfillment/package_preparation_status.dart';
import '../../../orders/domain/models/order_id.dart';

/// Starts and persists a new [PackagePreparation] record for [orderId], at
/// [PackagePreparationStatus.received] — the first stage every order's
/// packaging record begins at, regardless of channel.
class StartPackagePreparation {
  const StartPackagePreparation({
    required PackagePreparationRepository repository,
  }) : _repository = repository;

  final PackagePreparationRepository _repository;

  Future<PackagePreparation> call({
    required OrderId orderId,
    List<PackageChecklistItem> checklist = const [],
    String orderNotes = '',
  }) async {
    final preparation = PackagePreparation(
      orderId: orderId,
      status: PackagePreparationStatus.received,
      checklist: checklist,
      orderNotes: orderNotes,
      revision: 1,
    );
    await _repository.save(preparation);
    return preparation;
  }
}
