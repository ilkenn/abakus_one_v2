import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_status.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/advance_kitchen_order.dart';
import 'package:abakus_one_v2/features/pos/data/kitchen_action_gateway.dart';
import 'package:abakus_one_v2/features/pos/domain/kds/kitchen_line_status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/kds_test_fixtures.dart';
import '../../test_support/recording_kitchen_action_gateway.dart';

void main() {
  group('startPreparing', () {
    test(
        'advances the order confirmed -> preparing first, then walks each '
        'not-yet-started line to preparing one exact step at a time', () async {
      final gateway = RecordingKitchenActionGateway();
      await AdvanceKitchenOrder(gateway: gateway).startPreparing(
        orderId: 'order-1',
        channel: OrderChannel.dineInQr,
        workItems: [
          buildTestKitchenWorkItem(workItemId: 'w-queued', revision: 1),
          buildTestKitchenWorkItem(
              workItemId: 'w-ack',
              status: KitchenLineStatus.acknowledged,
              revision: 4),
          buildTestKitchenWorkItem(
              workItemId: 'w-prep', status: KitchenLineStatus.preparing),
          buildTestKitchenWorkItem(
              workItemId: 'w-cancelled', status: KitchenLineStatus.cancelled),
        ],
      );

      expect(gateway.calls, [
        'order:order-1/dineInQr->preparing',
        'line:w-queued->acknowledged@1',
        'line:w-queued->preparing@2',
        'line:w-ack->preparing@4',
      ]);
    });
  });

  group('markReady', () {
    test(
        'from preparing: moves every active line to ready, then the order '
        'preparing -> ready — never skipping', () async {
      final gateway = RecordingKitchenActionGateway();
      await AdvanceKitchenOrder(gateway: gateway).markReady(
        orderId: 'order-1',
        channel: OrderChannel.takeaway,
        currentStatus: OrderStatus.preparing,
        workItems: [
          buildTestKitchenWorkItem(
              workItemId: 'w-prep',
              status: KitchenLineStatus.preparing,
              revision: 3),
          buildTestKitchenWorkItem(
              workItemId: 'w-recalled',
              status: KitchenLineStatus.recalled,
              revision: 7),
          buildTestKitchenWorkItem(
              workItemId: 'w-ready', status: KitchenLineStatus.ready),
          buildTestKitchenWorkItem(
              workItemId: 'w-wasted', status: KitchenLineStatus.wasted),
        ],
      );

      expect(gateway.calls, [
        'line:w-prep->ready@3',
        'line:w-recalled->preparing@7',
        'line:w-recalled->ready@8',
        'order:order-1/takeaway->ready',
      ]);
    });

    test(
        'from a still-confirmed order: goes through preparing before ready '
        '(the exact bug: confirmed -> ready was rejected)', () async {
      final gateway = RecordingKitchenActionGateway();
      await AdvanceKitchenOrder(gateway: gateway).markReady(
        orderId: 'order-1',
        channel: OrderChannel.dineInQr,
        currentStatus: OrderStatus.confirmed,
        workItems: [buildTestKitchenWorkItem(workItemId: 'w-1')],
      );

      expect(gateway.calls, [
        'order:order-1/dineInQr->preparing',
        'line:w-1->acknowledged@1',
        'line:w-1->preparing@2',
        'line:w-1->ready@3',
        'order:order-1/dineInQr->ready',
      ]);
    });
  });

  group('handOver', () {
    for (final entry in {
      OrderChannel.dineInQr: 'served',
      OrderChannel.reservationPreorder: 'served',
      OrderChannel.takeaway: 'completed',
    }.entries) {
      test('${entry.key.name}: ready -> ${entry.value}', () async {
        final gateway = RecordingKitchenActionGateway();
        await AdvanceKitchenOrder(gateway: gateway)
            .handOver(orderId: 'order-1', channel: entry.key);
        expect(
            gateway.calls, ['order:order-1/${entry.key.name}->${entry.value}']);
      });
    }

    test('delivery is refused (courier hand-off) and calls nothing', () async {
      final gateway = RecordingKitchenActionGateway();
      await expectLater(
        AdvanceKitchenOrder(gateway: gateway)
            .handOver(orderId: 'order-1', channel: OrderChannel.delivery),
        throwsA(isA<KitchenActionException>()),
      );
      expect(gateway.calls, isEmpty);
    });
  });

  group('cancel', () {
    test('dispatches to the gateway with the raw channel name', () async {
      final gateway = RecordingKitchenActionGateway();
      await AdvanceKitchenOrder(gateway: gateway).cancel(
        orderId: 'order-1',
        channel: OrderChannel.delivery,
        reasonCode: DineInCancellationReasonCode.guestLeft,
      );
      expect(gateway.calls, ['cancel:order-1/delivery/guestLeft']);
    });

    test('dineInStaff (no backend lifecycle callable) is refused', () async {
      final gateway = RecordingKitchenActionGateway();
      await expectLater(
        AdvanceKitchenOrder(gateway: gateway).cancel(
          orderId: 'order-1',
          channel: OrderChannel.dineInStaff,
          reasonCode: DineInCancellationReasonCode.other,
        ),
        throwsA(isA<KitchenActionException>()),
      );
      expect(gateway.calls, isEmpty);
    });
  });

  group('syncOrderAfterLineTransition', () {
    test('last line ready on a still-confirmed order: preparing, then ready',
        () async {
      final gateway = RecordingKitchenActionGateway();
      await AdvanceKitchenOrder(gateway: gateway).syncOrderAfterLineTransition(
        orderId: 'order-1',
        channel: OrderChannel.dineInQr,
        currentStatus: OrderStatus.confirmed,
        lineTarget: KitchenLineStatus.ready,
        allSiblingsReady: true,
      );
      expect(gateway.calls, [
        'order:order-1/dineInQr->preparing',
        'order:order-1/dineInQr->ready',
      ]);
    });

    test('last line ready on a preparing order: ready only', () async {
      final gateway = RecordingKitchenActionGateway();
      await AdvanceKitchenOrder(gateway: gateway).syncOrderAfterLineTransition(
        orderId: 'order-1',
        channel: OrderChannel.takeaway,
        currentStatus: OrderStatus.preparing,
        lineTarget: KitchenLineStatus.ready,
        allSiblingsReady: true,
      );
      expect(gateway.calls, ['order:order-1/takeaway->ready']);
    });

    test('a line starting preparation moves a confirmed order to preparing',
        () async {
      final gateway = RecordingKitchenActionGateway();
      await AdvanceKitchenOrder(gateway: gateway).syncOrderAfterLineTransition(
        orderId: 'order-1',
        channel: OrderChannel.dineInQr,
        currentStatus: OrderStatus.confirmed,
        lineTarget: KitchenLineStatus.preparing,
        allSiblingsReady: false,
      );
      expect(gateway.calls, ['order:order-1/dineInQr->preparing']);
    });

    test('acknowledging a line, or siblings still pending: no order call',
        () async {
      final gateway = RecordingKitchenActionGateway();
      final useCase = AdvanceKitchenOrder(gateway: gateway);
      await useCase.syncOrderAfterLineTransition(
        orderId: 'order-1',
        channel: OrderChannel.dineInQr,
        currentStatus: OrderStatus.confirmed,
        lineTarget: KitchenLineStatus.acknowledged,
        allSiblingsReady: false,
      );
      await useCase.syncOrderAfterLineTransition(
        orderId: 'order-1',
        channel: OrderChannel.dineInQr,
        currentStatus: OrderStatus.preparing,
        lineTarget: KitchenLineStatus.ready,
        allSiblingsReady: false,
      );
      expect(gateway.calls, isEmpty);
    });

    test('dineInStaff is skipped silently (no lifecycle callable)', () async {
      final gateway = RecordingKitchenActionGateway();
      await AdvanceKitchenOrder(gateway: gateway).syncOrderAfterLineTransition(
        orderId: 'order-1',
        channel: OrderChannel.dineInStaff,
        currentStatus: OrderStatus.confirmed,
        lineTarget: KitchenLineStatus.ready,
        allSiblingsReady: true,
      );
      expect(gateway.calls, isEmpty);
    });
  });
}
