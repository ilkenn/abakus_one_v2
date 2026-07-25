enum NotificationType {
  orderStatus,
  courierApproaching,
  campaign,
  coupon,
  loyaltyPoint,
  accountSecurity,
}

enum NotificationPermission { prompt, granted, denied, permanentlyDenied }

class NotificationPayload {
  final String id;
  final String title;
  final String body;
  final NotificationType type;
  final String? deepLinkUrl;
  final Map<String, dynamic> data;

  const NotificationPayload({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    this.deepLinkUrl,
    this.data = const {},
  });
}
