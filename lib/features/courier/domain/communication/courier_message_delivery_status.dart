/// One recipient courier's delivered/read/acknowledged progress for one
/// [CourierMessage] — "manager sees: delivered, read, acknowledged,
/// timestamp." Built fresh by `BuildCourierMessageStatus`, never
/// persisted itself.
class CourierMessageDeliveryStatus {
  const CourierMessageDeliveryStatus({
    required this.messageId,
    required this.courierId,
    this.deliveredAt,
    this.readAt,
    this.acknowledgedAt,
  });

  final String messageId;
  final String courierId;
  final DateTime? deliveredAt;
  final DateTime? readAt;
  final DateTime? acknowledgedAt;
}
