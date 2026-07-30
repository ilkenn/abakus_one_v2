import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/courier/application/identity/courier_message_id_generator.dart';
import 'package:abakus_one_v2/features/courier/application/identity/courier_message_status_event_id_generator.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/acknowledge_emergency_message.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/build_courier_message_status.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/record_courier_message_status.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/send_courier_message.dart';
import 'package:abakus_one_v2/features/courier/data/courier_message_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_message_status_event_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_operational_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/courier/domain/audit/courier_audit_event_type.dart';
import 'package:abakus_one_v2/features/courier/domain/communication/courier_message_status_event.dart';
import 'package:abakus_one_v2/features/courier/domain/communication/courier_message_type.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/authorization_result.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../pos/test_support/fake_clock.dart';
import '../../pos/test_support/fake_pos_authorization_policy.dart';
import '../test_support/courier_test_fixtures.dart';

void main() {
  group('SendCourierMessage', () {
    CourierMessageRepository messageRepository =
        InMemoryCourierMessageRepository();
    late CourierOperationalAuditEntryRepository auditRepository;

    setUp(() {
      messageRepository = InMemoryCourierMessageRepository();
      auditRepository = InMemoryCourierOperationalAuditEntryRepository();
    });

    SendCourierMessage buildUseCase({required bool granted}) {
      return SendCourierMessage(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        authorizationPolicy:
            FakePosAuthorizationPolicy(AuthorizationResult(granted: granted)),
        idGenerator: SequentialCourierMessageIdGenerator(),
        repository: messageRepository,
        auditRepository: auditRepository,
        recordCourierEvent: buildTestRecordCourierEvent(),
      );
    }

    test('a direct message requires a recipient', () async {
      final useCase = buildUseCase(granted: true);
      await expectLater(
        () => useCase(
          branchId: 'branch-1',
          type: CourierMessageType.direct,
          body: 'Merhaba',
          performedByStaffId: 'manager-1',
        ),
        throwsA(isA<InvalidCourierMessageRecipientViolation>()),
      );
    });

    test('a direct message with a recipient is sent and audited', () async {
      final useCase = buildUseCase(granted: true);
      final message = await useCase(
        branchId: 'branch-1',
        type: CourierMessageType.direct,
        recipientCourierId: 'courier-1',
        body: 'Merhaba',
        performedByStaffId: 'manager-1',
      );

      expect(message.recipientCourierId, 'courier-1');
      final entries = await auditRepository.findByCourierId('courier-1');
      expect(
        entries
            .where((e) => e.type == CourierAuditEventType.courierMessageSent),
        isNotEmpty,
      );
    });

    test('a broadcast message must not have a recipient', () async {
      final useCase = buildUseCase(granted: true);
      await expectLater(
        () => useCase(
          branchId: 'branch-1',
          type: CourierMessageType.broadcast,
          recipientCourierId: 'courier-1',
          body: 'Herkese duyuru',
          performedByStaffId: 'manager-1',
        ),
        throwsA(isA<InvalidCourierMessageRecipientViolation>()),
      );
    });

    test('a broadcast message with no recipient is sent normally', () async {
      final useCase = buildUseCase(granted: true);
      final message = await useCase(
        branchId: 'branch-1',
        type: CourierMessageType.broadcast,
        body: 'Herkese duyuru',
        performedByStaffId: 'manager-1',
      );
      expect(message.recipientCourierId, isNull);
      expect(message.type, CourierMessageType.broadcast);
    });

    test('an emergency message is sent normally with no recipient', () async {
      final useCase = buildUseCase(granted: true);
      final message = await useCase(
        branchId: 'branch-1',
        type: CourierMessageType.emergency,
        body: 'Acil durum!',
        performedByStaffId: 'manager-1',
      );
      expect(message.type, CourierMessageType.emergency);
    });

    test('denied authorization throws and writes nothing', () async {
      final useCase = buildUseCase(granted: false);
      await expectLater(
        () => useCase(
          branchId: 'branch-1',
          type: CourierMessageType.direct,
          recipientCourierId: 'courier-1',
          body: 'Merhaba',
          performedByStaffId: 'courier-2',
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
      expect(await messageRepository.findByBranchId('branch-1'), isEmpty);
    });

    test(
        'findForCourier returns direct messages to the courier plus '
        'every broadcast/emergency message', () async {
      final useCase = buildUseCase(granted: true);
      await useCase(
        branchId: 'branch-1',
        type: CourierMessageType.direct,
        recipientCourierId: 'courier-1',
        body: 'Sana özel',
        performedByStaffId: 'manager-1',
      );
      await useCase(
        branchId: 'branch-1',
        type: CourierMessageType.direct,
        recipientCourierId: 'courier-2',
        body: 'Başkasına özel',
        performedByStaffId: 'manager-1',
      );
      await useCase(
        branchId: 'branch-1',
        type: CourierMessageType.broadcast,
        body: 'Herkese',
        performedByStaffId: 'manager-1',
      );

      final inbox = await messageRepository.findForCourier(
        courierId: 'courier-1',
        branchId: 'branch-1',
      );
      expect(inbox.map((m) => m.body).toSet(), {'Sana özel', 'Herkese'});
    });
  });

  group('RecordCourierMessageStatus', () {
    test('records a delivered or read event', () async {
      final repository = InMemoryCourierMessageStatusEventRepository();
      final useCase = RecordCourierMessageStatus(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        idGenerator: SequentialCourierMessageStatusEventIdGenerator(),
        repository: repository,
      );

      await useCase(
        messageId: 'msg-1',
        courierId: 'courier-1',
        type: CourierMessageStatusEventType.delivered,
      );
      await useCase(
        messageId: 'msg-1',
        courierId: 'courier-1',
        type: CourierMessageStatusEventType.read,
      );

      final events = await repository.findByMessageId('msg-1');
      expect(events, hasLength(2));
    });

    test('rejects being used to record an acknowledgement directly', () async {
      final useCase = RecordCourierMessageStatus(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        idGenerator: SequentialCourierMessageStatusEventIdGenerator(),
        repository: InMemoryCourierMessageStatusEventRepository(),
      );
      await expectLater(
        () => useCase(
          messageId: 'msg-1',
          courierId: 'courier-1',
          type: CourierMessageStatusEventType.acknowledged,
        ),
        throwsA(isA<MessageAcknowledgementNotRequiredViolation>()),
      );
    });
  });

  group('AcknowledgeEmergencyMessage', () {
    test('acknowledges a genuine emergency message and audits it', () async {
      final messageRepository = InMemoryCourierMessageRepository();
      final sendUseCase = SendCourierMessage(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        idGenerator: SequentialCourierMessageIdGenerator(),
        repository: messageRepository,
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
        recordCourierEvent: buildTestRecordCourierEvent(),
      );
      final emergency = await sendUseCase(
        branchId: 'branch-1',
        type: CourierMessageType.emergency,
        body: 'Acil!',
        performedByStaffId: 'manager-1',
      );

      final statusRepository = InMemoryCourierMessageStatusEventRepository();
      final auditRepository = InMemoryCourierOperationalAuditEntryRepository();
      final useCase = AcknowledgeEmergencyMessage(
        clock: FakeClock(DateTime(2026, 1, 1, 12, 1)),
        idGenerator: SequentialCourierMessageStatusEventIdGenerator(),
        messageRepository: messageRepository,
        statusRepository: statusRepository,
        auditRepository: auditRepository,
        recordCourierEvent: buildTestRecordCourierEvent(),
      );

      final event = await useCase(
        messageId: emergency.id,
        courierId: 'courier-1',
        branchId: 'branch-1',
      );

      expect(event.type, CourierMessageStatusEventType.acknowledged);
      final status = await BuildCourierMessageStatus(
        repository: statusRepository,
      )(messageId: emergency.id);
      expect(status.single.acknowledgedAt, isNotNull);
      final entries = await auditRepository.findByCourierId('courier-1');
      expect(
        entries.where((e) =>
            e.type == CourierAuditEventType.emergencyMessageAcknowledged),
        isNotEmpty,
      );
    });

    test('rejects acknowledging a non-emergency message', () async {
      final messageRepository = InMemoryCourierMessageRepository();
      final sendUseCase = SendCourierMessage(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        idGenerator: SequentialCourierMessageIdGenerator(),
        repository: messageRepository,
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
        recordCourierEvent: buildTestRecordCourierEvent(),
      );
      final direct = await sendUseCase(
        branchId: 'branch-1',
        type: CourierMessageType.direct,
        recipientCourierId: 'courier-1',
        body: 'Merhaba',
        performedByStaffId: 'manager-1',
      );

      final useCase = AcknowledgeEmergencyMessage(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        idGenerator: SequentialCourierMessageStatusEventIdGenerator(),
        messageRepository: messageRepository,
        statusRepository: InMemoryCourierMessageStatusEventRepository(),
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
        recordCourierEvent: buildTestRecordCourierEvent(),
      );

      await expectLater(
        () => useCase(
          messageId: direct.id,
          courierId: 'courier-1',
          branchId: 'branch-1',
        ),
        throwsA(isA<MessageAcknowledgementNotRequiredViolation>()),
      );
    });

    test('rejects acknowledging an unknown message id', () async {
      final useCase = AcknowledgeEmergencyMessage(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        idGenerator: SequentialCourierMessageStatusEventIdGenerator(),
        messageRepository: InMemoryCourierMessageRepository(),
        statusRepository: InMemoryCourierMessageStatusEventRepository(),
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
        recordCourierEvent: buildTestRecordCourierEvent(),
      );
      await expectLater(
        () => useCase(
          messageId: 'unknown',
          courierId: 'courier-1',
          branchId: 'branch-1',
        ),
        throwsA(isA<MessageAcknowledgementNotRequiredViolation>()),
      );
    });
  });

  group('BuildCourierMessageStatus', () {
    test('groups delivered/read/acknowledged by courier independently',
        () async {
      final repository = InMemoryCourierMessageStatusEventRepository();
      final recorder = RecordCourierMessageStatus(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        idGenerator: SequentialCourierMessageStatusEventIdGenerator(),
        repository: repository,
      );
      await recorder(
        messageId: 'msg-1',
        courierId: 'courier-1',
        type: CourierMessageStatusEventType.delivered,
      );
      await recorder(
        messageId: 'msg-1',
        courierId: 'courier-2',
        type: CourierMessageStatusEventType.delivered,
      );
      await recorder(
        messageId: 'msg-1',
        courierId: 'courier-2',
        type: CourierMessageStatusEventType.read,
      );

      final statuses = await BuildCourierMessageStatus(repository: repository)(
          messageId: 'msg-1');

      final courier1 = statuses.firstWhere((s) => s.courierId == 'courier-1');
      final courier2 = statuses.firstWhere((s) => s.courierId == 'courier-2');
      expect(courier1.deliveredAt, isNotNull);
      expect(courier1.readAt, isNull);
      expect(courier2.deliveredAt, isNotNull);
      expect(courier2.readAt, isNotNull);
    });
  });
}
