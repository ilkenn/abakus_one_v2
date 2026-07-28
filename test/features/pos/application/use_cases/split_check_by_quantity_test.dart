import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/cart/domain/models/cart_item.dart';
import 'package:abakus_one_v2/features/pos/application/identity/check_id_generator.dart';
import 'package:abakus_one_v2/features/pos/application/identity/pos_order_line_draft_id_generator.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/split_check_by_quantity.dart';
import 'package:abakus_one_v2/features/pos/data/check_repository.dart';
import 'package:abakus_one_v2/features/pos/data/pos_order_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/models/check.dart';
import 'package:abakus_one_v2/features/pos/domain/models/check_status.dart';
import 'package:abakus_one_v2/features/qr/data/table_session_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_clock.dart';
import '../../test_support/pos_test_fixtures.dart';

void main() {
  test('splits a quantity off the source line into a new check', () async {
    final checkRepository = InMemoryCheckRepository();
    final posOrderRepository = InMemoryPosOrderRepository();
    final tableSessionRepository = InMemoryTableSessionRepository();

    final session = buildTestSession(sessionId: 'check-a-session').copyWith(
      lines: [
        buildTestLineDraft(
          id: 'line-1',
          item: const CartItem(
              id: 'p1', name: 'Bowl A', desc: '', price: 100.0, quantity: 3),
        ),
      ],
    );
    await posOrderRepository.saveDraft('check-a-session', session);
    await checkRepository.save(Check(
      id: 'check-a',
      tableSessionId: 'tsession-1',
      branchId: 'branch-1',
      status: CheckStatus.open,
      posOrderSessionId: 'check-a-session',
      openedAt: DateTime(2026, 7, 29),
      revision: 1,
    ));

    final useCase = SplitCheckByQuantity(
      clock: FakeClock(DateTime(2026, 7, 29)),
      checkIdGenerator: SequentialCheckIdGenerator(),
      draftIdGenerator: SequentialPosOrderLineDraftIdGenerator(),
      checkRepository: checkRepository,
      posOrderRepository: posOrderRepository,
      tableSessionRepository: tableSessionRepository,
    );

    final newCheck = await useCase(
      sourceCheckId: 'check-a',
      orderLineDraftId: 'line-1',
      quantityToSplitOff: 1,
      openedByStaffId: 'staff-1',
    );

    final remaining = await posOrderRepository.getDraft('check-a-session');
    expect(remaining!.lines.single.item.quantity, 2);
    final newSession =
        await posOrderRepository.getDraft(newCheck.posOrderSessionId!);
    expect(newSession!.lines.single.item.quantity, 1);
  });

  test('rejects splitting off the entire quantity', () async {
    final checkRepository = InMemoryCheckRepository();
    final posOrderRepository = InMemoryPosOrderRepository();
    final session = buildTestSession(sessionId: 'check-a-session').copyWith(
      lines: [
        buildTestLineDraft(
          id: 'line-1',
          item: const CartItem(
              id: 'p1', name: 'Bowl A', desc: '', price: 100.0, quantity: 1),
        ),
      ],
    );
    await posOrderRepository.saveDraft('check-a-session', session);
    await checkRepository.save(Check(
      id: 'check-a',
      tableSessionId: 'tsession-1',
      branchId: 'branch-1',
      status: CheckStatus.open,
      posOrderSessionId: 'check-a-session',
      openedAt: DateTime(2026, 7, 29),
      revision: 1,
    ));
    final useCase = SplitCheckByQuantity(
      clock: FakeClock(DateTime(2026, 7, 29)),
      checkIdGenerator: SequentialCheckIdGenerator(),
      draftIdGenerator: SequentialPosOrderLineDraftIdGenerator(),
      checkRepository: checkRepository,
      posOrderRepository: posOrderRepository,
      tableSessionRepository: InMemoryTableSessionRepository(),
    );

    expect(
      () => useCase(
        sourceCheckId: 'check-a',
        orderLineDraftId: 'line-1',
        quantityToSplitOff: 1,
        openedByStaffId: 'staff-1',
      ),
      throwsA(isA<NonPositiveQuantityViolation>()),
    );
  });
}
