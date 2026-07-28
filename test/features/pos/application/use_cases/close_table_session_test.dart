import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/close_table_session.dart';
import 'package:abakus_one_v2/features/pos/data/check_repository.dart';
import 'package:abakus_one_v2/features/pos/data/order_closure_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/models/check.dart';
import 'package:abakus_one_v2/features/pos/domain/models/check_status.dart';
import 'package:abakus_one_v2/features/pos/domain/models/order_closure.dart';
import 'package:abakus_one_v2/features/pos/domain/models/order_closure_lifecycle_status.dart';
import 'package:abakus_one_v2/features/qr/data/table_session_repository.dart';
import 'package:abakus_one_v2/features/qr/domain/models/table_session.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_clock.dart';

TableSession _session({List<String> checkIds = const []}) {
  return TableSession(
    id: 'tsession-1',
    restaurantId: 'restaurant-1',
    branchId: 'branch-1',
    tableId: 'table-1',
    status: TableSessionStatus.active,
    openedAt: DateTime(2026, 7, 29),
    guestSessionIds: const [],
    activeOrderIds: const [],
    checkIds: checkIds,
  );
}

void main() {
  test('closes when every check is cancelled', () async {
    final tableSessionRepository = InMemoryTableSessionRepository();
    await tableSessionRepository.save(_session(checkIds: const ['check-1']));
    final checkRepository = InMemoryCheckRepository();
    await checkRepository.save(Check(
      id: 'check-1',
      tableSessionId: 'tsession-1',
      branchId: 'branch-1',
      status: CheckStatus.cancelled,
      openedAt: DateTime(2026, 7, 29),
      revision: 2,
    ));
    final useCase = CloseTableSession(
      clock: FakeClock(DateTime(2026, 7, 29)),
      tableSessionRepository: tableSessionRepository,
      checkRepository: checkRepository,
      orderClosureRepository: InMemoryOrderClosureRepository(),
    );

    final result = await useCase('tsession-1');

    expect(result.status, TableSessionStatus.closed);
  });

  test('throws when a submitted check has no closed OrderClosure yet',
      () async {
    final tableSessionRepository = InMemoryTableSessionRepository();
    await tableSessionRepository.save(_session(checkIds: const ['check-1']));
    final checkRepository = InMemoryCheckRepository();
    await checkRepository.save(Check(
      id: 'check-1',
      tableSessionId: 'tsession-1',
      branchId: 'branch-1',
      status: CheckStatus.submitted,
      orderId: OrderId('order-1'),
      openedAt: DateTime(2026, 7, 29),
      revision: 2,
    ));
    final useCase = CloseTableSession(
      clock: FakeClock(DateTime(2026, 7, 29)),
      tableSessionRepository: tableSessionRepository,
      checkRepository: checkRepository,
      orderClosureRepository: InMemoryOrderClosureRepository(),
    );

    expect(
      () => useCase('tsession-1'),
      throwsA(isA<TableSessionNotReadyToCloseViolation>()),
    );
  });

  test('closes once the submitted check\'s OrderClosure is closed', () async {
    final tableSessionRepository = InMemoryTableSessionRepository();
    await tableSessionRepository.save(_session(checkIds: const ['check-1']));
    final checkRepository = InMemoryCheckRepository();
    await checkRepository.save(Check(
      id: 'check-1',
      tableSessionId: 'tsession-1',
      branchId: 'branch-1',
      status: CheckStatus.submitted,
      orderId: OrderId('order-1'),
      openedAt: DateTime(2026, 7, 29),
      revision: 2,
    ));
    final orderClosureRepository = InMemoryOrderClosureRepository();
    await orderClosureRepository.save(OrderClosure(
      closureId: 'closure-1',
      orderId: OrderId('order-1'),
      lifecycleStatus: OrderClosureLifecycleStatus.closed,
      revision: 1,
    ));
    final useCase = CloseTableSession(
      clock: FakeClock(DateTime(2026, 7, 29)),
      tableSessionRepository: tableSessionRepository,
      checkRepository: checkRepository,
      orderClosureRepository: orderClosureRepository,
    );

    final result = await useCase('tsession-1');

    expect(result.status, TableSessionStatus.closed);
  });
}
