import 'package:abakus_one_v2/features/cart/domain/models/cart_item.dart';
import 'package:abakus_one_v2/features/pos/application/identity/check_id_generator.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/split_check_by_item.dart';
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
  test('splits the requested lines off into a brand-new check', () async {
    final checkRepository = InMemoryCheckRepository();
    final posOrderRepository = InMemoryPosOrderRepository();
    final tableSessionRepository = InMemoryTableSessionRepository();
    await tableSessionRepository.save(TableSession(
      id: 'tsession-1',
      restaurantId: 'restaurant-1',
      branchId: 'branch-1',
      tableId: 'table-1',
      status: TableSessionStatus.active,
      openedAt: DateTime(2026, 7, 29),
      guestSessionIds: const [],
      activeOrderIds: const [],
      checkIds: const ['check-a'],
    ));

    final session = buildTestSession(sessionId: 'check-a-session').copyWith(
      lines: [
        buildTestLineDraft(
          id: 'line-1',
          item: const CartItem(
              id: 'p1', name: 'Bowl A', desc: '', price: 100.0, quantity: 1),
        ),
        buildTestLineDraft(
          id: 'line-2',
          item: const CartItem(
              id: 'p2', name: 'Bowl B', desc: '', price: 120.0, quantity: 1),
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

    final useCase = SplitCheckByItem(
      clock: FakeClock(DateTime(2026, 7, 29)),
      idGenerator: SequentialCheckIdGenerator(),
      checkRepository: checkRepository,
      posOrderRepository: posOrderRepository,
      tableSessionRepository: tableSessionRepository,
    );

    final newCheck = await useCase(
      sourceCheckId: 'check-a',
      orderLineDraftIds: const ['line-2'],
      openedByStaffId: 'staff-1',
    );

    final remainingSession =
        await posOrderRepository.getDraft('check-a-session');
    expect(remainingSession!.lines.map((d) => d.id), ['line-1']);
    final newSession =
        await posOrderRepository.getDraft(newCheck.posOrderSessionId!);
    expect(newSession!.lines.map((d) => d.id), ['line-2']);
    final tableSession = await tableSessionRepository.findById('tsession-1');
    expect(tableSession!.checkIds, contains(newCheck.id));
  });
}
