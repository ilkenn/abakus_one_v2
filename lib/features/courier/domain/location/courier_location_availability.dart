import 'location_unavailable_reason.dart';

/// Whether a courier's device is currently reporting usable location —
/// **the gate this sprint's REQUIRED correction hangs every operational
/// action on**: "a courier must not be operationally usable without
/// location access during an active shift." Append-only via [revision],
/// mirroring `CourierAvailability`'s own shape — a new report is always a
/// new revision, never a mutation.
enum CourierLocationAvailabilityStatus { available, unavailable }

class CourierLocationAvailability {
  const CourierLocationAvailability({
    required this.courierId,
    required this.status,
    this.reason,
    this.deviceId,
    required this.updatedAt,
    required this.revision,
  });

  final String courierId;
  final CourierLocationAvailabilityStatus status;

  /// Required when [status] is [CourierLocationAvailabilityStatus.unavailable]
  /// — always a predefined [LocationUnavailableReason], never free text.
  final LocationUnavailableReason? reason;

  final String? deviceId;
  final DateTime updatedAt;
  final int revision;

  bool get isAvailable => status == CourierLocationAvailabilityStatus.available;
}
