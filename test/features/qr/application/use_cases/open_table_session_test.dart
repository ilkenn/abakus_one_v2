import 'package:abakus_one_v2/features/qr/application/identity/table_session_id_generator.dart';
import 'package:abakus_one_v2/features/qr/application/use_cases/open_table_session.dart';
import 'package:abakus_one_v2/features/qr/data/table_session_repository.dart';
import 'package:abakus_one_v2/features/qr/domain/models/table_session.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../pos/test_support/fake_clock.dart';

void main() {
  test('opens a new, active table session and persists it', () async {
    final repository = InMemoryTableSessionRepository();
    final useCase = OpenTableSession(
      clock: FakeClock(DateTime(2026, 7, 29)),
      idGenerator: SequentialTableSessionIdGenerator(),
      repository: repository,
    );

    final session = await useCase(
      restaurantId: 'restaurant-1',
      branchId: 'branch-1',
      tableId: 'table-1',
    );

    expect(session.status, TableSessionStatus.active);
    expect(session.tableId, 'table-1');
    expect(await repository.findById(session.id), session);
  });

  test('two calls always produce distinct new sessions, never reusing one',
      () async {
    final repository = InMemoryTableSessionRepository();
    final useCase = OpenTableSession(
      clock: FakeClock(DateTime(2026, 7, 29)),
      idGenerator: SequentialTableSessionIdGenerator(),
      repository: repository,
    );

    final first = await useCase(
        restaurantId: 'restaurant-1', branchId: 'branch-1', tableId: 'table-1');
    final second = await useCase(
        restaurantId: 'restaurant-1', branchId: 'branch-1', tableId: 'table-1');

    expect(first.id, isNot(second.id));
  });
}
