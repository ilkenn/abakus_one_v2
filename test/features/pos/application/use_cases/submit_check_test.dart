import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/cart/domain/models/cart_item.dart';
import 'package:abakus_one_v2/features/orders/domain/identity/order_identity.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/submit_check.dart';
import 'package:abakus_one_v2/features/pos/data/check_repository.dart';
import 'package:abakus_one_v2/features/pos/data/pos_order_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/models/check.dart';
import 'package:abakus_one_v2/features/pos/domain/models/check_status.dart';
import 'package:abakus_one_v2/features/qr/data/table_session_repository.dart';
import 'package:abakus_one_v2/features/qr/domain/models/table_session.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_clock.dart';
import '../../test_support/pos_test_fixtures.dart';

void main() {
  test('submits an open check into a real Order and links the table session',
      () async {
    final checkRepository = InMemoryCheckRepository();
    final posOrderRepository = InMemoryPosOrderRepository();
    final tableSessionRepository = InMemoryTableSessionRepository();

    final session = buildTestSession(sessionId: 'check-1-session').copyWith(
      lines: [
        buildTestLineDraft(
          item: const CartItem(
            id: 'p1',
            name: 'Mexifit Bowl',
            desc: '',
            price: 194.0,
            quantity: 1,
          ),
        ),
      ],
    );
    await posOrderRepository.saveDraft('check-1-session', session);
    await tableSessionRepository.save(TableSession(
      id: 'tsession-1',
      restaurantId: 'restaurant-1',
      branchId: 'branch-1',
      tableId: 'table-1',
      status: TableSessionStatus.active,
      openedAt: DateTime(2026, 7, 29),
      guestSessionIds: const [],
      activeOrderIds: const [],
      checkIds: const ['check-1'],
    ));
    final check = Check(
      id: 'check-1',
      tableSessionId: 'tsession-1',
      branchId: 'branch-1',
      status: CheckStatus.open,
      posOrderSessionId: 'check-1-session',
      openedAt: DateTime(2026, 7, 29),
      revision: 1,
    );
    await checkRepository.save(check);

    final useCase = SubmitCheck(
      clock: FakeClock(DateTime(2026, 7, 29)),
      identityProvider: InMemoryOrderIdentityProvider(),
      restaurantId: 'restaurant-abakus',
      checkRepository: checkRepository,
      posOrderRepository: posOrderRepository,
      tableSessionRepository: tableSessionRepository,
    );

    final order = await useCase(check);

    expect(order.lines, hasLength(1));
    final updatedCheck = await checkRepository.findById('check-1');
    expect(updatedCheck!.status, CheckStatus.submitted);
    expect(updatedCheck.orderId, order.id);
    final updatedSession = await tableSessionRepository.findById('tsession-1');
    expect(updatedSession!.activeOrderIds, [order.id.value]);
  });

  test('throws CheckNotOpenViolation for an already-submitted check', () async {
    final checkRepository = InMemoryCheckRepository();
    final check = Check(
      id: 'check-1',
      tableSessionId: 'tsession-1',
      branchId: 'branch-1',
      status: CheckStatus.cancelled,
      openedAt: DateTime(2026, 7, 29),
      revision: 1,
    );
    await checkRepository.save(check);

    final useCase = SubmitCheck(
      clock: FakeClock(DateTime(2026, 7, 29)),
      identityProvider: InMemoryOrderIdentityProvider(),
      restaurantId: 'restaurant-abakus',
      checkRepository: checkRepository,
      posOrderRepository: InMemoryPosOrderRepository(),
      tableSessionRepository: InMemoryTableSessionRepository(),
    );

    expect(() => useCase(check), throwsA(isA<CheckNotOpenViolation>()));
  });
}
