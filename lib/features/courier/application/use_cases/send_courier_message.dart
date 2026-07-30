import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/courier_message_repository.dart';
import '../../data/courier_operational_audit_entry_repository.dart';
import '../../domain/audit/courier_audit_event_type.dart';
import '../../domain/audit/courier_operational_audit_entry.dart';
import '../../domain/communication/courier_message.dart';
import '../../domain/communication/courier_message_type.dart';
import '../../domain/events/courier_event_type.dart';
import '../identity/courier_message_id_generator.dart';
import 'record_courier_event.dart';

/// Sends one [CourierMessage] — Sprint 5C Part 8's Communication Center.
/// Handles all three message kinds through one authorized, audited path
/// rather than three near-duplicate use cases:
/// [CourierMessageType.direct] (manager↔courier chat, requires
/// [recipientCourierId], gated by
/// [PosAuthorizedAction.sendCourierMessage]),
/// [CourierMessageType.broadcast] (every courier on shift for the branch,
/// no [recipientCourierId], gated by
/// [PosAuthorizedAction.sendBroadcastMessage]), and
/// [CourierMessageType.emergency] (full-screen,
/// acknowledgement-required — see `AcknowledgeEmergencyMessage` — gated by
/// [PosAuthorizedAction.sendEmergencyMessage]).
///
/// See [CourierMessage]'s own doc comment for this app's honest
/// same-process real-time boundary — this use case never claims genuine
/// cross-device push.
class SendCourierMessage {
  const SendCourierMessage({
    required Clock clock,
    required PosAuthorizationPolicy authorizationPolicy,
    required CourierMessageIdGenerator idGenerator,
    required CourierMessageRepository repository,
    required CourierOperationalAuditEntryRepository auditRepository,
    required RecordCourierEvent recordCourierEvent,
  })  : _clock = clock,
        _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _repository = repository,
        _auditRepository = auditRepository,
        _recordCourierEvent = recordCourierEvent;

  final Clock _clock;
  final PosAuthorizationPolicy _authorizationPolicy;
  final CourierMessageIdGenerator _idGenerator;
  final CourierMessageRepository _repository;
  final CourierOperationalAuditEntryRepository _auditRepository;
  final RecordCourierEvent _recordCourierEvent;

  static PosAuthorizedAction _actionFor(CourierMessageType type) {
    switch (type) {
      case CourierMessageType.direct:
        return PosAuthorizedAction.sendCourierMessage;
      case CourierMessageType.broadcast:
        return PosAuthorizedAction.sendBroadcastMessage;
      case CourierMessageType.emergency:
        return PosAuthorizedAction.sendEmergencyMessage;
    }
  }

  static CourierEventType _eventTypeFor(CourierMessageType type) {
    switch (type) {
      case CourierMessageType.direct:
        return CourierEventType.courierMessageSent;
      case CourierMessageType.broadcast:
        return CourierEventType.broadcastMessageSent;
      case CourierMessageType.emergency:
        return CourierEventType.emergencyMessageSent;
    }
  }

  static CourierAuditEventType _auditTypeFor(CourierMessageType type) {
    switch (type) {
      case CourierMessageType.direct:
        return CourierAuditEventType.courierMessageSent;
      case CourierMessageType.broadcast:
        return CourierAuditEventType.broadcastMessageSent;
      case CourierMessageType.emergency:
        return CourierAuditEventType.emergencyMessageSent;
    }
  }

  Future<CourierMessage> call({
    required String branchId,
    required CourierMessageType type,
    String? recipientCourierId,
    required String body,
    required String performedByStaffId,
  }) async {
    final needsRecipient = type == CourierMessageType.direct;
    if (needsRecipient && recipientCourierId == null) {
      throw InvalidCourierMessageRecipientViolation(typeName: type.name);
    }
    if (!needsRecipient && recipientCourierId != null) {
      throw InvalidCourierMessageRecipientViolation(typeName: type.name);
    }

    final action = _actionFor(type);
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
      context: {
        if (recipientCourierId != null) 'courierId': recipientCourierId
      },
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final now = _clock.now();
    final message = CourierMessage(
      id: _idGenerator.nextMessageId(),
      branchId: branchId,
      senderStaffId: performedByStaffId,
      recipientCourierId: recipientCourierId,
      type: type,
      body: body,
      sentAt: now,
    );
    await _repository.append(message);

    final event = await _recordCourierEvent(
      branchId: branchId,
      courierId: recipientCourierId,
      type: _eventTypeFor(type),
      idempotencyKey: '${message.id}-send',
      occurredAt: now,
      payload: {'messageType': type.name},
    );

    await _auditRepository.appendEvent(CourierOperationalAuditEntry(
      id: '${event.id}-audit',
      branchId: branchId,
      actorStaffId: performedByStaffId,
      courierId: recipientCourierId,
      type: _auditTypeFor(type),
      description: '${type.name} message sent'
          '${recipientCourierId == null ? '' : ' to "$recipientCourierId"'}',
      timestamp: now,
      correlationId: event.idempotencyKey,
    ));

    return message;
  }
}
