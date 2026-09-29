import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/qr/domain/models/table_session.dart';

TableSession buildSession({
  TableSessionStatus status = TableSessionStatus.active,
  List<String> guestSessionIds = const [],
  List<String> activeOrderIds = const [],
  List<String> checkIds = const [],
}) {
  return TableSession(
    id: 'session_1',
    restaurantId: 'restaurant_1',
    branchId: 'branch_1',
    tableId: 'table_1',
    status: status,
    openedAt: DateTime(2026, 6, 1, 12, 0),
    guestSessionIds: guestSessionIds,
    activeOrderIds: activeOrderIds,
    checkIds: checkIds,
  );
}

void main() {
  test('TableSessionStatus beklenen tum durumlari icerir', () {
    expect(TableSessionStatus.values, [
      TableSessionStatus.pending,
      TableSessionStatus.active,
      TableSessionStatus.closed,
      TableSessionStatus.cancelled,
    ]);
  });

  group('isOpen', () {
    test('pending acik kabul edilir', () {
      expect(buildSession(status: TableSessionStatus.pending).isOpen, isTrue);
    });

    test('active acik kabul edilir', () {
      expect(buildSession(status: TableSessionStatus.active).isOpen, isTrue);
    });

    test('closed acik kabul edilmez', () {
      expect(buildSession(status: TableSessionStatus.closed).isOpen, isFalse);
    });

    test('cancelled acik kabul edilmez', () {
      expect(
        buildSession(status: TableSessionStatus.cancelled).isOpen,
        isFalse,
      );
    });
  });

  test('withGuestAdded aynı misafiri tekrar eklemez', () {
    final session = buildSession(guestSessionIds: const ['guest_1']);
    final updated = session.withGuestAdded('guest_1');

    expect(updated.guestSessionIds, ['guest_1']);
  });

  test('withGuestAdded yeni misafiri listeye ekler (coklu misafir destegi)',
      () {
    final session = buildSession(guestSessionIds: const ['guest_1']);
    final updated = session.withGuestAdded('guest_2');

    expect(updated.guestSessionIds, ['guest_1', 'guest_2']);
  });

  test('withOrderAdded aktif siparis listesine ekler (coklu siparis destegi)',
      () {
    final session = buildSession(activeOrderIds: const ['order_1']);
    final updated = session.withOrderAdded('order_2');

    expect(updated.activeOrderIds, ['order_1', 'order_2']);
  });

  test('closed() durumu kapatir ve closedAt atar', () {
    final session = buildSession(status: TableSessionStatus.active);
    final closedAt = DateTime(2026, 6, 1, 13, 30);
    final closed = session.closed(at: closedAt);

    expect(closed.status, TableSessionStatus.closed);
    expect(closed.closedAt, closedAt);
    expect(closed.isOpen, isFalse);
  });

  test('cancelled() durumu iptal eder ve closedAt atar', () {
    final session = buildSession(status: TableSessionStatus.pending);
    final cancelledAt = DateTime(2026, 6, 1, 12, 5);
    final cancelled = session.cancelled(at: cancelledAt);

    expect(cancelled.status, TableSessionStatus.cancelled);
    expect(cancelled.closedAt, cancelledAt);
  });

  test('withCheckAdded aynı adisyonu tekrar eklemez (Sprint 3D)', () {
    final session = buildSession(checkIds: const ['check_1']);
    final updated = session.withCheckAdded('check_1');

    expect(updated.checkIds, ['check_1']);
  });

  test('withCheckAdded yeni adisyonu listeye ekler (Sprint 3D)', () {
    final session = buildSession(checkIds: const ['check_1']);
    final updated = session.withCheckAdded('check_2');

    expect(updated.checkIds, ['check_1', 'check_2']);
  });

  test('withCheckRemoved adisyonu listeden cikarir (Sprint 3D)', () {
    final session = buildSession(checkIds: const ['check_1', 'check_2']);
    final updated = session.withCheckRemoved('check_1');

    expect(updated.checkIds, ['check_2']);
  });

  test('withCheckRemoved listede olmayan bir id icin no-op olur (Sprint 3D)',
      () {
    final session = buildSession(checkIds: const ['check_1']);
    final updated = session.withCheckRemoved('missing');

    expect(updated.checkIds, ['check_1']);
  });

  test('canAcceptNewGuest yalnizca active durumda true doner', () {
    expect(
      buildSession(status: TableSessionStatus.active).canAcceptNewGuest,
      isTrue,
    );
    expect(
      buildSession(status: TableSessionStatus.pending).canAcceptNewGuest,
      isFalse,
    );
  });

  // 2026-09-29 — Client Staleness Check: expiresAt is optional (many
  // construction sites unrelated to QR guest sessions never set it) but
  // must round-trip correctly wherever it is set.
  group('expiresAt', () {
    test('varsayilan olarak null doner', () {
      expect(buildSession().expiresAt, isNull);
    });

    test('kurucudan verilen deger dogru saklanir', () {
      final expiresAt = DateTime(2026, 6, 1, 18, 0);
      final session = TableSession(
        id: 'session_1',
        restaurantId: 'restaurant_1',
        branchId: 'branch_1',
        tableId: 'table_1',
        status: TableSessionStatus.active,
        openedAt: DateTime(2026, 6, 1, 12, 0),
        guestSessionIds: const [],
        activeOrderIds: const [],
        expiresAt: expiresAt,
      );

      expect(session.expiresAt, expiresAt);
    });

    test('copyWith ile guncellenebilir, verilmezse korunur', () {
      final expiresAt = DateTime(2026, 6, 1, 18, 0);
      final session = TableSession(
        id: 'session_1',
        restaurantId: 'restaurant_1',
        branchId: 'branch_1',
        tableId: 'table_1',
        status: TableSessionStatus.active,
        openedAt: DateTime(2026, 6, 1, 12, 0),
        guestSessionIds: const [],
        activeOrderIds: const [],
        expiresAt: expiresAt,
      );

      expect(session.copyWith().expiresAt, expiresAt);

      final laterExpiry = DateTime(2026, 6, 1, 20, 0);
      expect(
        session.copyWith(expiresAt: laterExpiry).expiresAt,
        laterExpiry,
      );
    });
  });
}
