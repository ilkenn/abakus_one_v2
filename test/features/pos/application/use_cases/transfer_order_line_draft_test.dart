import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/cart/domain/models/cart_item.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/transfer_order_line_draft.dart';
import 'package:abakus_one_v2/features/pos/data/check_repository.dart';
import 'package:abakus_one_v2/features/pos/data/pos_order_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/models/check.dart';
import 'package:abakus_one_v2/features/pos/domain/models/check_status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_clock.dart';
import '../../test_support/pos_test_fixtures.dart';

Future<Check> _openCheckWithLine(
  CheckRepository checkRepository,
  PosOrderRepository posOrderRepository,
  String checkId,
) async {
  final session = buildTestSession(sessionId: '$checkId-session').copyWith(
    lines: [
      buildTestLineDraft(
        id: '$checkId-line',
        item: const CartItem(
            id: 'p1',
            name: 'Mexifit Bowl',
            desc: '',
            price: 194.0,
            quantity: 1),
      ),
    ],
  );
  await posOrderRepository.saveDraft(session.sessionId, session);
  final check = Check(
    id: checkId,
    tableSessionId: 'tsession-1',
    branchId: 'branch-1',
    status: CheckStatus.open,
    posOrderSessionId: session.sessionId,
    openedAt: DateTime(2026, 7, 29),
    revision: 1,
  );
  await checkRepository.save(check);
  return check;
}

void main() {
  test('moves a line from the source session into the target session',
      () async {
    final checkRepository = InMemoryCheckRepository();
    final posOrderRepository = InMemoryPosOrderRepository();
    await _openCheckWithLine(checkRepository, posOrderRepository, 'check-a');
    await _openCheckWithLine(checkRepository, posOrderRepository, 'check-b');
    // check-b starts with its own line too; only check-a's line moves.
    final useCase = TransferOrderLineDraft(
      clock: FakeClock(DateTime(2026, 7, 29)),
      checkRepository: checkRepository,
      posOrderRepository: posOrderRepository,
    );

    await useCase(
      sourceCheckId: 'check-a',
      targetCheckId: 'check-b',
      orderLineDraftId: 'check-a-line',
    );

    final sourceSession = await posOrderRepository.getDraft('check-a-session');
    final targetSession = await posOrderRepository.getDraft('check-b-session');
    expect(sourceSession!.lines, isEmpty);
    expect(targetSession!.lines.map((d) => d.id),
        containsAll(['check-a-line', 'check-b-line']));
  });

  test('throws CheckNotOpenViolation when the target is not open', () async {
    final checkRepository = InMemoryCheckRepository();
    final posOrderRepository = InMemoryPosOrderRepository();
    await _openCheckWithLine(checkRepository, posOrderRepository, 'check-a');
    await checkRepository.save(Check(
      id: 'check-b',
      tableSessionId: 'tsession-1',
      branchId: 'branch-1',
      status: CheckStatus.submitted,
      openedAt: DateTime(2026, 7, 29),
      revision: 2,
    ));
    final useCase = TransferOrderLineDraft(
      clock: FakeClock(DateTime(2026, 7, 29)),
      checkRepository: checkRepository,
      posOrderRepository: posOrderRepository,
    );

    expect(
      () => useCase(
        sourceCheckId: 'check-a',
        targetCheckId: 'check-b',
        orderLineDraftId: 'check-a-line',
      ),
      throwsA(isA<CheckNotOpenViolation>()),
    );
  });
}
