import 'package:abakus_one_v2/features/qr/data/table_session_repository.dart';
import 'package:abakus_one_v2/features/qr/domain/models/table_session.dart';
import 'package:flutter_test/flutter_test.dart';

TableSession _session({
  String id = 'tsession-1',
  String tableId = 'table-1',
  TableSessionStatus status = TableSessionStatus.active,
}) {
  return TableSession(
    id: id,
    restaurantId: 'restaurant-1',
    branchId: 'branch-1',
    tableId: tableId,
    status: status,
    openedAt: DateTime(2026, 7, 29),
    guestSessionIds: const [],
    activeOrderIds: const [],
  );
}

void main() {
  test('save then findById returns the saved session', () async {
    final repository = InMemoryTableSessionRepository();
    final session = _session();

    await repository.save(session);

    expect(await repository.findById('tsession-1'), session);
  });

  test('findActiveByTableId returns only an open session for that table',
      () async {
    final repository = InMemoryTableSessionRepository();
    await repository
        .save(_session(id: 'tsession-1', status: TableSessionStatus.closed));
    await repository
        .save(_session(id: 'tsession-2', status: TableSessionStatus.active));

    final active = await repository.findActiveByTableId('table-1');

    expect(active!.id, 'tsession-2');
  });

  test('findActiveByTableId returns null when no session is open', () async {
    final repository = InMemoryTableSessionRepository();
    await repository.save(_session(status: TableSessionStatus.closed));

    expect(await repository.findActiveByTableId('table-1'), isNull);
  });
}
