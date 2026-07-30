import 'courier_live_warning_type.dart';

/// One active warning for one courier — Sprint 5C Part 9. Built fresh by
/// `BuildCourierLiveWarnings`, never persisted itself.
class CourierLiveWarning {
  const CourierLiveWarning({
    required this.courierId,
    required this.branchId,
    required this.type,
    required this.description,
    required this.detectedAt,
  });

  final String courierId;
  final String branchId;
  final CourierLiveWarningType type;
  final String description;
  final DateTime detectedAt;
}
