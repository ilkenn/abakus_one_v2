import '../../../../core/errors/business_rule_violation.dart';
import '../../data/delivery_repository.dart';
import '../../domain/delivery/delivery.dart';
import '../../domain/delivery/delivery_status.dart';

/// Moves a [Delivery] from [DeliveryStatus.awaitingPackage] to
/// [DeliveryStatus.readyForAssignment] — the integration point a caller
/// invokes once the order's `PackagePreparation` (Sprint 3D) reaches a
/// packing-in-progress-or-further status. Deliberately not auto-triggered
/// by watching `PackagePreparation` events directly (that would couple
/// this feature tightly to `orders`' fulfillment internals beyond a
/// single reference read) — the caller (a screen or an orchestration
/// step) decides when to call this, exactly as `CompleteKitchenOrderPreparation`
/// (Phase 4) is itself caller-invoked rather than automatically fired.
class MarkDeliveryReadyForAssignment {
  const MarkDeliveryReadyForAssignment({required DeliveryRepository repository})
      : _repository = repository;

  final DeliveryRepository _repository;

  Future<Delivery> call({required String deliveryId}) async {
    final delivery = await _repository.findById(deliveryId);
    if (delivery == null) {
      throw UnknownCourierEntityViolation(
        entityName: 'Delivery',
        id: deliveryId,
      );
    }
    if (!DeliveryStatusTransitions.canTransition(
        delivery.status, DeliveryStatus.readyForAssignment)) {
      throw InvalidDeliveryTransitionViolation(
        fromStatusName: delivery.status.name,
        toStatusName: DeliveryStatus.readyForAssignment.name,
      );
    }

    final updated = delivery.copyWith(
      status: DeliveryStatus.readyForAssignment,
      revision: delivery.revision + 1,
    );
    await _repository.save(updated);
    return updated;
  }
}
