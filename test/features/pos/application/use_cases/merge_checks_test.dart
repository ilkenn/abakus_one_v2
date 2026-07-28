import 'package:abakus_one_v2/features/cart/domain/models/cart_item.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/merge_checks.dart';
import 'package:abakus_one_v2/features/pos/data/check_repository.dart';
import 'package:abakus_one_v2/features/pos/data/pos_order_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/models/check.dart';
import 'package:abakus_one_v2/features/pos/domain/models/check_status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_clock.dart';
import '../../test_support/pos_test_fixtures.dart';

void main() {
  test('merges source lines into target and cancels the source check',
      () async {
    final checkRepository = InMemoryCheckRepository();
    final posOrderRepository = InMemoryPosOrderRepository();

    final sourceSession =
        buildTestSession(sessionId: 'check-a-session').copyWith(lines: [
      buildTestLineDraft(
        id: 'line-a',
        item: const CartItem(
            id: 'p1', name: 'Bowl A', desc: '', price: 100.0, quantity: 1),
      ),
    ]);
    await posOrderRepository.saveDraft('check-a-session', sourceSession);
    await checkRepository.save(Check(
      id: 'check-a',
      tableSessionId: 'tsession-1',
      branchId: 'branch-1',
      status: CheckStatus.open,
      posOrderSessionId: 'check-a-session',
      openedAt: DateTime(2026, 7, 29),
      revision: 1,
    ));

    final targetSession =
        buildTestSession(sessionId: 'check-b-session').copyWith(lines: [
      buildTestLineDraft(
        id: 'line-b',
        item: const CartItem(
            id: 'p2', name: 'Bowl B', desc: '', price: 120.0, quantity: 1),
      ),
    ]);
    await posOrderRepository.saveDraft('check-b-session', targetSession);
    await checkRepository.save(Check(
      id: 'check-b',
      tableSessionId: 'tsession-1',
      branchId: 'branch-1',
      status: CheckStatus.open,
      posOrderSessionId: 'check-b-session',
      openedAt: DateTime(2026, 7, 29),
      revision: 1,
    ));

    final useCase = MergeChecks(
      clock: FakeClock(DateTime(2026, 7, 29)),
      checkRepository: checkRepository,
      posOrderRepository: posOrderRepository,
    );

    final cancelledSource =
        await useCase(sourceCheckId: 'check-a', targetCheckId: 'check-b');

    expect(cancelledSource.status, CheckStatus.cancelled);
    expect(await posOrderRepository.getDraft('check-a-session'), isNull);
    final merged = await posOrderRepository.getDraft('check-b-session');
    expect(merged!.lines.map((d) => d.id), ['line-b', 'line-a']);
  });
}
