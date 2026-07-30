import '../../data/courier_location_repository.dart';
import '../../data/courier_operational_audit_entry_repository.dart';
import '../../domain/delivery/delivery_tracking_history.dart';
import '../../domain/delivery/delivery_tracking_segment_builder.dart';

/// Assembles one delivery's [DeliveryTrackingHistory] from the existing,
/// unmodified `CourierLocationRepository` and
/// `CourierOperationalAuditEntryRepository` — Sprint 5B Part 10. A pure
/// read-model builder, no new persisted state, no authorization gate
/// (matches `BuildCourierLiveStatus`'s own precedent for the same
/// reasoning).
class BuildDeliveryTrackingHistory {
  const BuildDeliveryTrackingHistory({
    required CourierLocationRepository locationRepository,
    required CourierOperationalAuditEntryRepository auditRepository,
  })  : _locationRepository = locationRepository,
        _auditRepository = auditRepository;

  final CourierLocationRepository _locationRepository;
  final CourierOperationalAuditEntryRepository _auditRepository;

  Future<DeliveryTrackingHistory> call({required String deliveryId}) async {
    final locationHistory =
        await _locationRepository.findByDeliveryId(deliveryId);
    final sortedLocations = [...locationHistory]
      ..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));

    final checkpoints = await _auditRepository.findByDeliveryId(deliveryId);
    final sortedCheckpoints = [...checkpoints]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return DeliveryTrackingHistory(
      deliveryId: deliveryId,
      checkpoints: sortedCheckpoints,
      locationHistory: sortedLocations,
      segments: DeliveryTrackingSegmentBuilder.build(history: sortedLocations),
    );
  }
}
