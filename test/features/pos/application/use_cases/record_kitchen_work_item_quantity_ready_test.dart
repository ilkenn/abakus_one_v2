import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/mark_kitchen_ticket_line_ready.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/record_kitchen_work_item_quantity_ready.dart';
import 'package:abakus_one_v2/features/pos/data/kitchen_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/pos/data/kitchen_projection_repository.dart';
import 'package:abakus_one_v2/features/pos/data/kitchen_ticket_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/authorization_result.dart';
import 'package:abakus_one_v2/features/pos/domain/kds/kitchen_line_status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_clock.dart';
import '../../test_support/fake_pos_authorization_policy.dart';
import '../../test_support/kds_test_fixtures.dart';

void main() {
  group('RecordKitchenWorkItemQuantityReady', () {
    test('partial progress does not yet mark the line ready', () async {
      final projectionRepository = InMemoryKitchenProjectionRepository();
      final item = buildTestKitchenWorkItem(
        quantity: 3,
        status: KitchenLineStatus.preparing,
        preparingStartedAt: DateTime(2026, 1, 1, 12),
      );
      await projectionRepository.save(item);
      final ticketRepository = InMemoryKitchenTicketRepository();
      await ticketRepository.save(buildTestKitchenTicket());

      final useCase = RecordKitchenWorkItemQuantityReady(
        clock: FakeClock(DateTime(2026, 1, 1, 12, 5)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        projectionRepository: projectionRepository,
        auditRepository: InMemoryKitchenAuditEntryRepository(),
        recordKitchenEvent: buildTestRecordKitchenEvent(),
        markKitchenTicketLineReady: MarkKitchenTicketLineReady(
          clock: FakeClock(DateTime(2026, 1, 1, 12, 5)),
          repository: ticketRepository,
        ),
      );

      final updated = await useCase(
        workItemId: item.id,
        expectedRevision: item.revision,
        readyQuantityDelta: 2,
        performedByStaffId: 'staff-1',
      );

      expect(updated.readyQuantity, 2);
      expect(updated.status, KitchenLineStatus.preparing);
    });

    test(
        'reaching full quantity marks the line ready and bridges into '
        'KitchenTicket.orderReadyAt (Sprint 3D)', () async {
      final projectionRepository = InMemoryKitchenProjectionRepository();
      final item = buildTestKitchenWorkItem(
        quantity: 2,
        status: KitchenLineStatus.preparing,
        preparingStartedAt: DateTime(2026, 1, 1, 12),
      );
      await projectionRepository.save(item);
      final ticketRepository = InMemoryKitchenTicketRepository();
      await ticketRepository.save(buildTestKitchenTicket());

      final useCase = RecordKitchenWorkItemQuantityReady(
        clock: FakeClock(DateTime(2026, 1, 1, 12, 5)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        projectionRepository: projectionRepository,
        auditRepository: InMemoryKitchenAuditEntryRepository(),
        recordKitchenEvent: buildTestRecordKitchenEvent(),
        markKitchenTicketLineReady: MarkKitchenTicketLineReady(
          clock: FakeClock(DateTime(2026, 1, 1, 12, 5)),
          repository: ticketRepository,
        ),
      );

      final updated = await useCase(
        workItemId: item.id,
        expectedRevision: item.revision,
        readyQuantityDelta: 2,
        performedByStaffId: 'staff-1',
      );

      expect(updated.status, KitchenLineStatus.ready);
      expect(updated.readyAt, isNotNull);

      final ticket = await ticketRepository.findById('ticket-1');
      expect(ticket!.completedLineIds, contains('ticket-1-line-0'));
      expect(ticket.orderReadyAt, isNotNull);
    });

    test('throws when not preparing', () async {
      final projectionRepository = InMemoryKitchenProjectionRepository();
      final item = buildTestKitchenWorkItem();
      await projectionRepository.save(item);

      final useCase = RecordKitchenWorkItemQuantityReady(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        projectionRepository: projectionRepository,
        auditRepository: InMemoryKitchenAuditEntryRepository(),
        recordKitchenEvent: buildTestRecordKitchenEvent(),
        markKitchenTicketLineReady: MarkKitchenTicketLineReady(
          clock: FakeClock(DateTime(2026, 1, 1, 12)),
          repository: InMemoryKitchenTicketRepository(),
        ),
      );

      expect(
        () => useCase(
          workItemId: item.id,
          expectedRevision: item.revision,
          readyQuantityDelta: 1,
          performedByStaffId: 'staff-1',
        ),
        throwsA(isA<InvalidKitchenLineTransitionViolation>()),
      );
    });
  });
}
