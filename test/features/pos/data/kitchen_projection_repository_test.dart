import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/pos/data/kitchen_projection_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/kds/kitchen_line_status.dart';
import 'package:abakus_one_v2/features/pos/domain/kds/kitchen_station.dart';
import 'package:abakus_one_v2/features/pos/domain/kds/kitchen_work_item.dart';
import 'package:flutter_test/flutter_test.dart';

KitchenWorkItem _item({
  required String id,
  String branchId = 'branch-1',
  KitchenStation station = KitchenStation.shared,
  String orderId = 'order-1',
  int revision = 1,
}) {
  return KitchenWorkItem(
    id: id,
    branchId: branchId,
    station: station,
    orderId: OrderId(orderId),
    kitchenTicketId: 'ticket-1',
    kitchenTicketLineId: id,
    quantity: 1,
    status: KitchenLineStatus.queued,
    queuedAt: DateTime(2026, 1, 1),
    revision: revision,
    idempotencyKey: 'ticket-1-$id',
  );
}

void main() {
  group('InMemoryKitchenProjectionRepository', () {
    test('findById returns the latest saved revision', () async {
      final repository = InMemoryKitchenProjectionRepository();
      await repository.save(_item(id: 'w1'));
      await repository.save(_item(id: 'w1', revision: 2));

      final found = await repository.findById('w1');
      expect(found!.revision, 2);
    });

    test('findByIdempotencyKey resolves an existing item', () async {
      final repository = InMemoryKitchenProjectionRepository();
      await repository.save(_item(id: 'w1'));

      final found = await repository.findByIdempotencyKey('ticket-1-w1');
      expect(found!.id, 'w1');
      expect(await repository.findByIdempotencyKey('unknown'), isNull);
    });

    test('findByBranch filters by station when supplied', () async {
      final repository = InMemoryKitchenProjectionRepository();
      await repository.save(_item(id: 'w1', station: KitchenStation.hot));
      await repository.save(_item(id: 'w2', station: KitchenStation.cold));

      final hotOnly = await repository.findByBranch(
          branchId: 'branch-1', stationName: KitchenStation.hot.name);
      expect(hotOnly.map((i) => i.id), ['w1']);

      final all = await repository.findByBranch(branchId: 'branch-1');
      expect(all, hasLength(2));
    });

    test('findByBranch never returns another branch\'s items', () async {
      final repository = InMemoryKitchenProjectionRepository();
      await repository.save(_item(id: 'w1', branchId: 'branch-1'));
      await repository.save(_item(id: 'w2', branchId: 'branch-2'));

      final branch1Items = await repository.findByBranch(branchId: 'branch-1');
      expect(branch1Items.map((i) => i.id), ['w1']);
    });

    group('watchByOrderId', () {
      test('emits the current snapshot immediately on subscription',
          () async {
        final repository = InMemoryKitchenProjectionRepository();
        await repository.save(_item(id: 'w1', orderId: 'order-a'));

        final first =
            await repository.watchByOrderId(OrderId('order-a')).first;

        expect(first.map((i) => i.id), ['w1']);
      });

      test('re-emits when a new item is saved for the watched order',
          () async {
        final repository = InMemoryKitchenProjectionRepository();
        final emissions = <List<KitchenWorkItem>>[];
        final subscription = repository
            .watchByOrderId(OrderId('order-a'))
            .listen(emissions.add);
        await Future<void>.delayed(Duration.zero);

        await repository.save(_item(id: 'w1', orderId: 'order-a'));
        await Future<void>.delayed(Duration.zero);

        expect(emissions.last.map((i) => i.id), ['w1']);
        await subscription.cancel();
      });

      test(
          'a save for a different order does not emit on this order\'s stream',
          () async {
        final repository = InMemoryKitchenProjectionRepository();
        final emissions = <List<KitchenWorkItem>>[];
        final subscription = repository
            .watchByOrderId(OrderId('order-a'))
            .listen(emissions.add);
        await Future<void>.delayed(Duration.zero);
        final countAfterInitial = emissions.length;

        await repository.save(_item(id: 'w2', orderId: 'order-b'));
        await Future<void>.delayed(Duration.zero);

        expect(emissions.length, countAfterInitial);
        await subscription.cancel();
      });

      test(
          'a duplicate save (new revision) does not produce two entries for one work item',
          () async {
        final repository = InMemoryKitchenProjectionRepository();
        await repository.save(_item(id: 'w1', orderId: 'order-a'));
        await repository
            .save(_item(id: 'w1', orderId: 'order-a', revision: 2));

        final results =
            await repository.watchByOrderId(OrderId('order-a')).first;

        expect(results, hasLength(1));
        expect(results.single.revision, 2);
      });
    });
  });
}
