import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../data/courier_message_repository.dart';
import '../../data/courier_message_status_event_repository.dart';
import '../../data/courier_operational_audit_entry_repository.dart';
import '../../domain/audit/courier_audit_event_type.dart';
import '../../domain/audit/courier_operational_audit_entry.dart';
import '../../domain/communication/courier_message_status_event.dart';
import '../../domain/communication/courier_message_type.dart';
import '../../domain/events/courier_event_type.dart';
import '../identity/courier_message_status_event_id_generator.dart';
import 'record_courier_event.dart';

/// A courier acknowledges an emergency [CourierMessage] — "emergency
/// message must interrupt courier UI, requires acknowledgement" — Sprint
/// 5C Part 8. Throws [MessageAcknowledgementNotRequiredViolation] if
/// [messageId] does not refer to a [CourierMessageType.emergency]
/// message. System-triggered (the courier confirming they saw it), no
/// authorization gate — but always audited, since "manager sees
/// delivered/read/acknowledged/timestamp" depends on it.
class AcknowledgeEmergencyMessage {
  const AcknowledgeEmergencyMessage({
    required Clock clock,
    required CourierMessageStatusEventIdGenerator idGenerator,
    required CourierMessageRepository messageRepository,
    required CourierMessageStatusEventRepository statusRepository,
    required CourierOperationalAuditEntryRepository auditRepository,
    required RecordCourierEvent recordCourierEvent,
  })  : _clock = clock,
        _idGenerator = idGenerator,
        _messageRepository = messageRepository,
        _statusRepository = statusRepository,
        _auditRepository = auditRepository,
        _recordCourierEvent = recordCourierEvent;

  final Clock _clock;
  final CourierMessageStatusEventIdGenerator _idGenerator;
  final CourierMessageRepository _messageRepository;
  final CourierMessageStatusEventRepository _statusRepository;
  final CourierOperationalAuditEntryRepository _auditRepository;
  final RecordCourierEvent _recordCourierEvent;

  Future<CourierMessageStatusEvent> call({
    required String messageId,
    required String courierId,
    required String branchId,
  }) async {
    final messages = await _messageRepository.findByBranchId(branchId);
    CourierMessageType? matchedType;
    for (final message in messages) {
      if (message.id == messageId) {
        matchedType = message.type;
        break;
      }
    }
    if (matchedType != CourierMessageType.emergency) {
      throw MessageAcknowledgementNotRequiredViolation(messageId: messageId);
    }

    final now = _clock.now();
    final event = CourierMessageStatusEvent(
      id: _idGenerator.nextStatusEventId(),
      messageId: messageId,
      courierId: courierId,
      type: CourierMessageStatusEventType.acknowledged,
      occurredAt: now,
    );
    await _statusRepository.append(event);

    final courierEvent = await _recordCourierEvent(
      branchId: branchId,
      courierId: courierId,
      type: CourierEventType.emergencyMessageAcknowledged,
      idempotencyKey: '$messageId-ack-$courierId',
      occurredAt: now,
    );

    await _auditRepository.appendEvent(CourierOperationalAuditEntry(
      id: '${courierEvent.id}-audit',
      branchId: branchId,
      actorStaffId: courierId,
      courierId: courierId,
      type: CourierAuditEventType.emergencyMessageAcknowledged,
      description: 'Emergency message "$messageId" acknowledged',
      timestamp: now,
      correlationId: courierEvent.idempotencyKey,
    ));

    return event;
  }
}
