import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/application/use_cases/record_courier_cash_collection.dart'
    as pos;
import '../../../pos/domain/courier_settlement/courier_cash_collection.dart';
import '../../../pos/domain/courier_settlement/courier_collection_type.dart';
import '../../../../shared/models/money.dart';
import '../../data/delivery_repository.dart';

/// Records a courier's cash collection for one [Delivery] — a thin
/// wrapper over Sprint 3F's existing `RecordCourierCashCollection`
/// (`lib/features/pos/application/use_cases/`), called directly and
/// unchanged, never reimplemented. Reuses [Delivery.orderId] as the
/// collection's order reference — never a second, courier-feature-owned
/// financial record.
///
/// **Courier may declare collected cash. Courier may not financially
/// approve or settle it** — this use case only records the collection
/// (Sprint 3F's own `CourierCollectionType`); approval/settlement remain
/// entirely `ApproveCourierSettlement`/`RejectCourierSettlement`'s
/// responsibility (Sprint 3F, untouched, manager-only).
class DeclareCourierCashCollectionForDelivery {
  const DeclareCourierCashCollectionForDelivery({
    required pos.RecordCourierCashCollection recordCourierCashCollection,
    required DeliveryRepository deliveryRepository,
  })  : _recordCourierCashCollection = recordCourierCashCollection,
        _deliveryRepository = deliveryRepository;

  final pos.RecordCourierCashCollection _recordCourierCashCollection;
  final DeliveryRepository _deliveryRepository;

  Future<CourierCashCollection> call({
    required String deliveryId,
    required String settlementSessionId,
    required String paymentSessionId,
    required Money collectedAmount,
    required CourierCollectionType collectionType,
    String notes = '',
  }) async {
    final delivery = await _deliveryRepository.findById(deliveryId);
    if (delivery == null) {
      throw UnknownCourierEntityViolation(
        entityName: 'Delivery',
        id: deliveryId,
      );
    }

    return _recordCourierCashCollection(
      settlementSessionId: settlementSessionId,
      orderId: delivery.orderId,
      paymentSessionId: paymentSessionId,
      collectedAmount: collectedAmount,
      collectionType: collectionType,
      notes: notes,
    );
  }
}
