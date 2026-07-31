import '../../../../core/utils/clock.dart';
import '../../../orders/domain/models/order_id.dart';
import '../../data/delivery_repository.dart';
import '../../domain/delivery/delivery.dart';
import '../../domain/delivery/delivery_status.dart';
import '../identity/delivery_id_generator.dart';

/// Creates a new [Delivery] for a delivery-channel order — "delivery must
/// reference an existing delivery-channel order," and never duplicates
/// `Order`. Constructs at [DeliveryStatus.created] then immediately
/// advances to [DeliveryStatus.awaitingPackage] as a second saved
/// revision — both real, observable states, not skipped (unlike
/// `RequestCourierShift`'s deliberate `scheduled`-skip simplification,
/// reported in `docs/decisions.md` ADR-017).
///
/// **Sprint 5E**: idempotent per [orderId] — if a [Delivery] already
/// exists for [orderId] (`DeliveryRepository.findByOrderId`), that one is
/// returned unchanged instead of creating a second one. Defense in depth
/// for the new `CompleteKitchenOrderPreparation` hook
/// (`docs/decisions.md` ADR-022): that call site is already naturally
/// non-reentrant (a duplicate kitchen-completion event is rejected
/// earlier, at `RecordKitchenEvent`'s idempotency-key check, before this
/// use case is ever reached), but the guard belongs here too so
/// `CreateDelivery` is safe to call from any future caller as well.
class CreateDelivery {
  const CreateDelivery({
    required Clock clock,
    required DeliveryIdGenerator idGenerator,
    required DeliveryRepository repository,
  })  : _clock = clock,
        _idGenerator = idGenerator,
        _repository = repository;

  final Clock _clock;
  final DeliveryIdGenerator _idGenerator;
  final DeliveryRepository _repository;

  Future<Delivery> call({
    required OrderId orderId,
    required String branchId,
  }) async {
    final existing = await _repository.findByOrderId(orderId);
    if (existing != null) return existing;

    final now = _clock.now();
    final created = Delivery(
      id: _idGenerator.nextDeliveryId(),
      orderId: orderId,
      branchId: branchId,
      status: DeliveryStatus.created,
      createdAt: now,
      revision: 1,
    );
    await _repository.save(created);

    final awaitingPackage = created.copyWith(
      status: DeliveryStatus.awaitingPackage,
      revision: 2,
    );
    await _repository.save(awaitingPackage);

    return awaitingPackage;
  }
}
