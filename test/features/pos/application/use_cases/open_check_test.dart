import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/pos/application/identity/check_id_generator.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/open_check.dart';
import 'package:abakus_one_v2/features/pos/data/check_repository.dart';
import 'package:abakus_one_v2/features/pos/data/pos_order_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/models/check_status.dart';
import 'package:abakus_one_v2/features/qr/data/table_session_repository.dart';
import 'package:abakus_one_v2/features/qr/domain/models/table_session.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_clock.dart';

TableSession _session() {
  return TableSession(
    id: 'tsession-1',
    restaurantId: 'restaurant-1',
    branchId: 'branch-1',
    tableId: 'table-1',
    status: TableSessionStatus.active,
    openedAt: DateTime(2026, 7, 29),
    guestSessionIds: const [],
    activeOrderIds: const [],
  );
}

void main() {
  test('opens a check, starts its draft session, and links the table session',
      () async {
    final tableSessionRepository = InMemoryTableSessionRepository();
    await tableSessionRepository.save(_session());
    final posOrderRepository = InMemoryPosOrderRepository();
    final checkRepository = InMemoryCheckRepository();
    final useCase = OpenCheck(
      clock: FakeClock(DateTime(2026, 7, 29)),
      idGenerator: SequentialCheckIdGenerator(),
      tableSessionRepository: tableSessionRepository,
      posOrderRepository: posOrderRepository,
      checkRepository: checkRepository,
    );

    final check = await useCase(
      tableSessionId: 'tsession-1',
      openedByStaffId: 'staff-1',
    );

    expect(check.status, CheckStatus.open);
    expect(check.posOrderSessionId, isNotNull);
    expect(await checkRepository.findById(check.id), check);
    expect(
      await posOrderRepository.getDraft(check.posOrderSessionId!),
      isNotNull,
    );
    final updatedSession = await tableSessionRepository.findById('tsession-1');
    expect(updatedSession!.checkIds, [check.id]);
  });

  test(
      'throws UnknownRestaurantOperationsEntityViolation for an unknown table session',
      () async {
    final useCase = OpenCheck(
      clock: FakeClock(DateTime(2026, 7, 29)),
      idGenerator: SequentialCheckIdGenerator(),
      tableSessionRepository: InMemoryTableSessionRepository(),
      posOrderRepository: InMemoryPosOrderRepository(),
      checkRepository: InMemoryCheckRepository(),
    );

    expect(
      () => useCase(tableSessionId: 'missing', openedByStaffId: 'staff-1'),
      throwsA(isA<UnknownRestaurantOperationsEntityViolation>()),
    );
  });
}
