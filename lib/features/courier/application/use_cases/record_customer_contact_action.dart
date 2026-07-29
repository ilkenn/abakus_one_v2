import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../data/courier_operational_audit_entry_repository.dart';
import '../../data/customer_contact_action_repository.dart';
import '../../data/delivery_repository.dart';
import '../../domain/audit/courier_audit_event_type.dart';
import '../../domain/audit/courier_operational_audit_entry.dart';
import '../../domain/contact/customer_contact_action.dart';
import '../../domain/contact/customer_contact_action_type.dart';
import '../identity/customer_contact_action_id_generator.dart';

/// Logs a courier-initiated customer contact action. **Access is limited
/// to the active delivery window** — a contact action may only be
/// recorded while the [Delivery] is not yet terminal
/// (`Delivery.isTerminal`); once delivered/cancelled/returned, the
/// courier has no further reason to contact the customer and the action
/// is rejected.
///
/// **Never carries raw customer contact data** — [loggedNote] is an
/// operational note only (length-limited, matching `CourierFeedback`'s
/// 280-character limit) and must never contain a phone number or
/// address; that data never flows through this use case at all, since
/// [CustomerContactAction] itself has no field capable of holding it.
class RecordCustomerContactAction {
  const RecordCustomerContactAction({
    required Clock clock,
    required CustomerContactActionIdGenerator idGenerator,
    required DeliveryRepository deliveryRepository,
    required CustomerContactActionRepository actionRepository,
    required CourierOperationalAuditEntryRepository auditRepository,
  })  : _clock = clock,
        _idGenerator = idGenerator,
        _deliveryRepository = deliveryRepository,
        _actionRepository = actionRepository,
        _auditRepository = auditRepository;

  final Clock _clock;
  final CustomerContactActionIdGenerator _idGenerator;
  final DeliveryRepository _deliveryRepository;
  final CustomerContactActionRepository _actionRepository;
  final CourierOperationalAuditEntryRepository _auditRepository;

  static const _maxNoteLength = 280;

  Future<CustomerContactAction> call({
    required String deliveryId,
    required String courierId,
    required CustomerContactActionType type,
    String? loggedNote,
    required String performedByStaffId,
  }) async {
    final delivery = await _deliveryRepository.findById(deliveryId);
    if (delivery == null) {
      throw UnknownCourierEntityViolation(
        entityName: 'Delivery',
        id: deliveryId,
      );
    }
    if (delivery.isTerminal) {
      throw InvalidDeliveryTransitionViolation(
        fromStatusName: delivery.status.name,
        toStatusName: 'customerContactAction',
      );
    }
    if (delivery.courierId != courierId) {
      throw DeliveryNotAssignedToCourierViolation(
        deliveryId: deliveryId,
        courierId: courierId,
      );
    }

    final now = _clock.now();
    final truncatedNote =
        loggedNote != null && loggedNote.length > _maxNoteLength
            ? loggedNote.substring(0, _maxNoteLength)
            : loggedNote;

    final action = CustomerContactAction(
      id: _idGenerator.nextActionId(),
      deliveryId: deliveryId,
      courierId: courierId,
      type: type,
      initiatedAt: now,
      loggedNote: truncatedNote,
    );
    await _actionRepository.append(action);

    await _auditRepository.appendEvent(CourierOperationalAuditEntry(
      id: '${action.id}-audit',
      branchId: delivery.branchId,
      actorStaffId: performedByStaffId,
      courierId: courierId,
      orderId: delivery.orderId.value,
      deliveryId: deliveryId,
      type: CourierAuditEventType.customerContactAction,
      description: 'Customer contact action: ${type.name}',
      timestamp: now,
      correlationId: action.id,
    ));

    return action;
  }
}
