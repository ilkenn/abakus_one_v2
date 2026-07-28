import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/pos/data/order_closure_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/models/order_closure.dart';
import 'package:abakus_one_v2/features/pos/domain/models/order_closure_lifecycle_status.dart';
import 'package:flutter_test/flutter_test.dart';

OrderClosure _closure({
  String closureId = 'c1',
  String orderId = 'order-1',
  OrderClosureLifecycleStatus status = OrderClosureLifecycleStatus.open,
  int revision = 1,
}) {
  return OrderClosure(
    closureId: closureId,
    orderId: OrderId(orderId),
    lifecycleStatus: status,
    revision: revision,
  );
}

void main() {
  group('InMemoryOrderClosureRepository — append-only', () {
    test('save never overwrites a previous revision', () async {
      final repository = InMemoryOrderClosureRepository();
      await repository.save(_closure(revision: 1));
      await repository.save(_closure(revision: 2));

      expect(repository.allRevisions, hasLength(2));
    });

    test('findByClosureId returns the highest-revision entry', () async {
      final repository = InMemoryOrderClosureRepository();
      await repository.save(_closure(revision: 1, status: OrderClosureLifecycleStatus.open));
      await repository.save(_closure(revision: 2, status: OrderClosureLifecycleStatus.closed));

      final found = await repository.findByClosureId('c1');

      expect(found!.revision, 2);
      expect(found.lifecycleStatus, OrderClosureLifecycleStatus.closed);
    });

    test('findCurrentByOrderId returns the highest-revision entry for that order', () async {
      final repository = InMemoryOrderClosureRepository();
      await repository.save(_closure(revision: 1));
      await repository.save(_closure(revision: 2, status: OrderClosureLifecycleStatus.paymentInProgress));

      final current = await repository.findCurrentByOrderId(OrderId('order-1'));

      expect(current!.revision, 2);
    });

    test('findHistoryByOrderId returns every revision, oldest first', () async {
      final repository = InMemoryOrderClosureRepository();
      await repository.save(_closure(revision: 1));
      await repository.save(_closure(revision: 2, status: OrderClosureLifecycleStatus.paymentInProgress));
      await repository.save(_closure(revision: 3, status: OrderClosureLifecycleStatus.closed));

      final history = await repository.findHistoryByOrderId(OrderId('order-1'));

      expect(history, hasLength(3));
      expect(history.first.revision, 1);
      expect(history.last.revision, 3);
    });

    test('returns null for an unknown closure/order', () async {
      final repository = InMemoryOrderClosureRepository();
      expect(await repository.findByClosureId('nonexistent'), isNull);
      expect(await repository.findCurrentByOrderId(OrderId('nonexistent')), isNull);
    });

    test('findAllCurrent returns the latest revision of every distinct closureId', () async {
      final repository = InMemoryOrderClosureRepository();
      await repository.save(_closure(closureId: 'c1', revision: 1));
      await repository.save(_closure(closureId: 'c1', revision: 2, status: OrderClosureLifecycleStatus.closed));
      await repository.save(_closure(closureId: 'c2', orderId: 'order-2', revision: 1));

      final current = await repository.findAllCurrent();

      expect(current, hasLength(2));
      final c1 = current.firstWhere((c) => c.closureId == 'c1');
      expect(c1.revision, 2);
      expect(c1.lifecycleStatus, OrderClosureLifecycleStatus.closed);
    });
  });

  group('InMemoryOrderClosureRepository — failure injection', () {
    test('failOnSave throws once, then clears itself', () async {
      final repository = InMemoryOrderClosureRepository();
      repository.failOnSave = Exception('disk full');

      await expectLater(repository.save(_closure()), throwsException);
      await expectLater(repository.save(_closure()), completes);
    });
  });
}
