import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/pos/data/kitchen_event_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/kds/kitchen_event.dart';
import 'package:abakus_one_v2/features/pos/domain/kds/kitchen_event_type.dart';
import 'package:flutter_test/flutter_test.dart';

KitchenEvent _event({
  required String id,
  required String branchId,
  required String idempotencyKey,
  DateTime? occurredAt,
}) {
  return KitchenEvent(
    id: id,
    branchId: branchId,
    type: KitchenEventType.workItemQueued,
    idempotencyKey: idempotencyKey,
    sequence: 0,
    occurredAt: occurredAt ?? DateTime(2026, 1, 1),
  );
}

void main() {
  group('InMemoryKitchenEventRepository', () {
    test(
        'assigns monotonically increasing sequence per branch, ignoring '
        'occurredAt ordering (out-of-order delivery)', () async {
      final repository = InMemoryKitchenEventRepository();
      final first = await repository.append(_event(
        id: 'e1',
        branchId: 'branch-1',
        idempotencyKey: 'k1',
        occurredAt: DateTime(2026, 1, 1, 12, 5),
      ));
      final second = await repository.append(_event(
        id: 'e2',
        branchId: 'branch-1',
        idempotencyKey: 'k2',
        occurredAt: DateTime(2026, 1, 1, 12, 0),
      ));

      expect(first.sequence, 1);
      expect(second.sequence, 2);
    });

    test('rejects a duplicate idempotency key within the same branch',
        () async {
      final repository = InMemoryKitchenEventRepository();
      await repository
          .append(_event(id: 'e1', branchId: 'branch-1', idempotencyKey: 'k1'));

      expect(
        () => repository.append(
            _event(id: 'e2', branchId: 'branch-1', idempotencyKey: 'k1')),
        throwsA(isA<DuplicateKitchenEventViolation>()),
      );
    });

    test('the same idempotency key is allowed across different branches',
        () async {
      final repository = InMemoryKitchenEventRepository();
      await repository
          .append(_event(id: 'e1', branchId: 'branch-1', idempotencyKey: 'k1'));

      final second = await repository
          .append(_event(id: 'e2', branchId: 'branch-2', idempotencyKey: 'k1'));
      expect(second.sequence, 1);
    });

    test(
        'findSince returns events with sequence strictly greater than '
        'afterSequence, in order', () async {
      final repository = InMemoryKitchenEventRepository();
      await repository
          .append(_event(id: 'e1', branchId: 'branch-1', idempotencyKey: 'k1'));
      await repository
          .append(_event(id: 'e2', branchId: 'branch-1', idempotencyKey: 'k2'));
      await repository
          .append(_event(id: 'e3', branchId: 'branch-1', idempotencyKey: 'k3'));

      final since =
          await repository.findSince(branchId: 'branch-1', afterSequence: 1);
      expect(since.map((e) => e.id), ['e2', 'e3']);
    });

    test('latestSequence is 0 for an unknown branch', () async {
      final repository = InMemoryKitchenEventRepository();
      expect(await repository.latestSequence('unknown-branch'), 0);
    });
  });
}
