import 'customer_contact_action_type.dart';

/// One immutable, append-only log entry of a courier-initiated customer
/// contact action — "contact actions must be logged," and "contact
/// details must not be copied into courier audit records": this record
/// never carries a phone number, address, or any other raw customer
/// contact datum — only the fact that a contact action of [type]
/// happened, when, for which delivery.
class CustomerContactAction {
  const CustomerContactAction({
    required this.id,
    required this.deliveryId,
    required this.courierId,
    required this.type,
    required this.initiatedAt,
    this.loggedNote,
  });

  final String id;
  final String deliveryId;
  final String courierId;
  final CustomerContactActionType type;
  final DateTime initiatedAt;

  /// Operational note only (e.g. `'no answer'`) — never customer PII.
  final String? loggedNote;
}
