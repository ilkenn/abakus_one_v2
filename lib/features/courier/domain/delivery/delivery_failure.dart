import 'delivery_failure_reason.dart';
import 'delivery_failure_responsibility.dart';

/// One immutable, append-only record of a failed delivery/pickup attempt.
/// [responsibility] is derived from [reasonCode] at construction time via
/// `DeliveryFailureResponsibilityMapper` and frozen — never independently
/// settable, so a failure's responsibility can never disagree with its own
/// reason.
class DeliveryFailure {
  DeliveryFailure({
    required this.id,
    required this.deliveryId,
    required this.reasonCode,
    required this.courierNote,
    required this.recordedByStaffId,
    required this.recordedAt,
  }) : responsibility =
            DeliveryFailureResponsibilityMapper.forReason(reasonCode);

  final String id;
  final String deliveryId;
  final DeliveryFailureReason reasonCode;
  final DeliveryFailureResponsibility responsibility;

  /// Operational, length-limited free text — enforced by
  /// `RecordDeliveryFailure` (max 280 characters), never an unrestricted
  /// accusation field.
  final String courierNote;

  final String recordedByStaffId;
  final DateTime recordedAt;

  /// Only a customer-attributable failure may ever emit a customer-risk
  /// signal — see `RecordDeliveryFailure` and
  /// `docs/business_rules.md` BR-COURIER-*.
  bool get mayEmitCustomerRiskSignal =>
      responsibility == DeliveryFailureResponsibility.customer;
}
