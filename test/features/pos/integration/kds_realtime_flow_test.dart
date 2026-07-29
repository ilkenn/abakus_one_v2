import 'package:abakus_one_v2/features/orders/data/package_preparation_repository.dart';
import 'package:abakus_one_v2/features/orders/domain/fulfillment/package_preparation.dart';
import 'package:abakus_one_v2/features/orders/domain/fulfillment/package_preparation_status.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/pos/application/identity/kitchen_event_id_generator.dart';
import 'package:abakus_one_v2/features/pos/application/identity/kitchen_work_item_id_generator.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/complete_kitchen_order_preparation.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/enqueue_kitchen_work_items.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/mark_kitchen_ticket_line_ready.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/record_kitchen_event.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/record_kitchen_work_item_quantity_ready.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/transition_kitchen_work_item.dart';
import 'package:abakus_one_v2/features/pos/application/services/in_memory_kitchen_synchronization_service.dart';
import 'package:abakus_one_v2/features/pos/data/in_memory_kitchen_event_bus.dart';
import 'package:abakus_one_v2/features/pos/data/kitchen_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/pos/data/kitchen_event_cursor_repository.dart';
import 'package:abakus_one_v2/features/pos/data/kitchen_event_repository.dart';
import 'package:abakus_one_v2/features/pos/data/kitchen_projection_repository.dart';
import 'package:abakus_one_v2/features/pos/data/kitchen_routing_rule_repository.dart';
import 'package:abakus_one_v2/features/pos/data/kitchen_ticket_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/authorization_result.dart';
import 'package:abakus_one_v2/features/pos/domain/kds/kitchen_line_status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/fake_clock.dart';
import '../test_support/fake_pos_authorization_policy.dart';
import '../test_support/kds_test_fixtures.dart';

void main() {
  test(
      'fire ticket -> enqueue -> two devices sync -> lifecycle to ready -> '
      'complete order preparation -> package preparation bridge, end to end',
      () async {
    // --- Shared in-memory infrastructure (one branch). ---
    final projectionRepository = InMemoryKitchenProjectionRepository();
    final eventRepository = InMemoryKitchenEventRepository();
    final eventBus = InMemoryKitchenEventBus();
    final auditRepository = InMemoryKitchenAuditEntryRepository();
    final ticketRepository = InMemoryKitchenTicketRepository();
    final routingRuleRepository = InMemoryKitchenRoutingRuleRepository();
    final cursorRepository = InMemoryKitchenEventCursorRepository();
    final authorizationPolicy =
        FakePosAuthorizationPolicy(const AuthorizationResult(granted: true));

    RecordKitchenEvent recordEvent() => RecordKitchenEvent(
          idGenerator: SequentialKitchenEventIdGenerator(),
          eventRepository: eventRepository,
          eventPublisher: eventBus,
        );

    final ticket = buildTestKitchenTicket(lineCount: 1);
    await ticketRepository.save(ticket);

    // --- Phase 4D: enqueue routed work items from the fired ticket. ---
    final enqueue = EnqueueKitchenWorkItems(
      clock: FakeClock(DateTime(2026, 1, 1, 12)),
      idGenerator: SequentialKitchenWorkItemIdGenerator(),
      projectionRepository: projectionRepository,
      routingRuleRepository: routingRuleRepository,
      recordKitchenEvent: recordEvent(),
    );
    final created = await enqueue(ticket: ticket);
    expect(created, hasLength(1));
    final workItem = created.single;

    // --- Phase 4G: two devices, both starting from an empty cursor. ---
    final syncService = InMemoryKitchenSynchronizationService(
      clock: FakeClock(DateTime(2026, 1, 1, 12)),
      eventRepository: eventRepository,
      cursorRepository: cursorRepository,
    );
    final deviceASync = await syncService.synchronize(
        deviceId: 'device-A', branchId: 'branch-1');
    final deviceBSync = await syncService.synchronize(
        deviceId: 'device-B', branchId: 'branch-1');
    expect(deviceASync.events, hasLength(1));
    expect(deviceBSync.events, hasLength(1));

    // --- Phase 4B: device A drives the line through the lifecycle. ---
    final transition = TransitionKitchenWorkItem(
      clock: FakeClock(DateTime(2026, 1, 1, 12, 5)),
      authorizationPolicy: authorizationPolicy,
      projectionRepository: projectionRepository,
      auditRepository: auditRepository,
      recordKitchenEvent: recordEvent(),
    );
    final acknowledged = await transition(
      workItemId: workItem.id,
      to: KitchenLineStatus.acknowledged,
      expectedRevision: workItem.revision,
      performedByStaffId: 'staff-1',
      deviceId: 'device-A',
    );
    final preparing = await transition(
      workItemId: workItem.id,
      to: KitchenLineStatus.preparing,
      expectedRevision: acknowledged.revision,
      performedByStaffId: 'staff-1',
      deviceId: 'device-A',
    );

    final markReady = RecordKitchenWorkItemQuantityReady(
      clock: FakeClock(DateTime(2026, 1, 1, 12, 10)),
      authorizationPolicy: authorizationPolicy,
      projectionRepository: projectionRepository,
      auditRepository: auditRepository,
      recordKitchenEvent: recordEvent(),
      markKitchenTicketLineReady: MarkKitchenTicketLineReady(
        clock: FakeClock(DateTime(2026, 1, 1, 12, 10)),
        repository: ticketRepository,
      ),
    );
    final ready = await markReady(
      workItemId: workItem.id,
      expectedRevision: preparing.revision,
      readyQuantityDelta: 1,
      performedByStaffId: 'staff-1',
      deviceId: 'device-A',
    );
    expect(ready.status, KitchenLineStatus.ready);

    // --- Device B, which never acted, still catches up correctly via a
    // fresh synchronize call (reconnect synchronization). ---
    final deviceBCatchUp = await syncService.synchronize(
        deviceId: 'device-B', branchId: 'branch-1');
    expect(
        deviceBCatchUp.events, hasLength(3)); // acknowledged, preparing, ready
    expect(deviceBCatchUp.events.last.type.name, 'workItemReady');

    // --- Phase 4H: complete order preparation bridges into
    // PackagePreparation for a delivery order. ---
    final packagePreparationRepository = InMemoryPackagePreparationRepository();
    await packagePreparationRepository.save(PackagePreparation(
      orderId: OrderId('order-1'),
      status: PackagePreparationStatus.preparing,
      revision: 1,
    ));

    final completeOrder = CompleteKitchenOrderPreparation(
      clock: FakeClock(DateTime(2026, 1, 1, 12, 15)),
      authorizationPolicy: authorizationPolicy,
      projectionRepository: projectionRepository,
      auditRepository: auditRepository,
      recordKitchenEvent: recordEvent(),
      advanceToReadyForPacking: ({
        required orderId,
        required performedByStaffId,
        required at,
      }) async {
        final current =
            await packagePreparationRepository.findCurrentByOrderId(orderId);
        await packagePreparationRepository.save(current!.copyWith(
          status: PackagePreparationStatus.readyForPacking,
          revision: current.revision + 1,
        ));
      },
    );
    await completeOrder(
      orderId: OrderId('order-1'),
      kitchenTicketId: ticket.id,
      branchId: 'branch-1',
      channel: OrderChannel.delivery,
      performedByStaffId: 'staff-1',
    );

    final finalPackagePrep = await packagePreparationRepository
        .findCurrentByOrderId(OrderId('order-1'));
    expect(finalPackagePrep!.status, PackagePreparationStatus.readyForPacking);

    // --- Audit completeness: every state-changing action left a trace. ---
    final auditEntries = await auditRepository.findByOrderId('order-1');
    expect(auditEntries.map((e) => e.type.name), [
      'acknowledged',
      'preparationStarted',
      'markedReady',
      'orderPreparationCompleted',
    ]);
  });
}
