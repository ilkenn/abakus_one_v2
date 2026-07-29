import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/courier/data/courier_event_repository.dart';
import 'package:abakus_one_v2/features/courier/domain/events/courier_event.dart';
import 'package:abakus_one_v2/features/courier/domain/events/courier_event_type.dart';
import 'package:flutter_test/flutter_test.dart';

CourierEvent _event({
  required String id,
  required String branchId,
  required String idempotencyKey,
  DateTime? occurredAt,
}) {
  return CourierEvent(
    id: id,
    branchId: branchId,
    type: CourierEventType.deliveryCreated,
    idempotencyKey: idempotencyKey,
    sequence: 0,
    occurredAt: occurredAt ?? DateTime(2026, 1, 1),
  );
}

void main() {
  group('InMemoryCourierEventRepository', () {
    test(
        'assigns monotonically increasing sequence per branch, ignoring '
        'occurredAt ordering (out-of-order delivery)', () async {
      final repository = InMemoryCourierEventRepository();
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
      final repository = InMemoryCourierEventRepository();
      await repository
          .append(_event(id: 'e1', branchId: 'branch-1', idempotencyKey: 'k1'));

      expect(
        () => repository.append(
            _event(id: 'e2', branchId: 'branch-1', idempotencyKey: 'k1')),
        throwsA(isA<DuplicateCourierEventViolation>()),
      );
    });

    test('the same idempotency key is allowed across different branches',
        () async {
      final repository = InMemoryCourierEventRepository();
      await repository
          .append(_event(id: 'e1', branchId: 'branch-1', idempotencyKey: 'k1'));

      final second = await repository
          .append(_event(id: 'e2', branchId: 'branch-2', idempotencyKey: 'k1'));
      expect(second.sequence, 1);
    });

    test(
        'findSince returns events with sequence strictly greater than '
        'afterSequence, in order', () async {
      final repository = InMemoryCourierEventRepository();
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
      final repository = InMemoryCourierEventRepository();
      expect(await repository.latestSequence('unknown-branch'), 0);
    });
  });
}
