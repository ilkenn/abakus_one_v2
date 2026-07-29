import 'package:abakus_one_v2/features/pos/data/courier_settlement_session_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/courier_settlement/courier_settlement_session.dart';
import 'package:abakus_one_v2/features/pos/domain/courier_settlement/courier_settlement_session_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InMemoryCourierSettlementSessionRepository', () {
    test('findById returns the latest saved revision', () async {
      final repository = InMemoryCourierSettlementSessionRepository();
      final v1 = CourierSettlementSession(
        id: 's1',
        courierId: 'courier-1',
        branchId: 'branch-1',
        status: CourierSettlementSessionStatus.active,
        openedAt: DateTime(2026, 7, 29),
        revision: 1,
      );
      await repository.save(v1);
      final v2 = v1.copyWith(
        status: CourierSettlementSessionStatus.pendingApproval,
        revision: 2,
      );
      await repository.save(v2);

      final found = await repository.findById('s1');
      expect(found!.status, CourierSettlementSessionStatus.pendingApproval);
      expect(found.revision, 2);
    });

    test('findActiveByCourierId returns null once the session is closed',
        () async {
      final repository = InMemoryCourierSettlementSessionRepository();
      final session = CourierSettlementSession(
        id: 's1',
        courierId: 'courier-1',
        branchId: 'branch-1',
        status: CourierSettlementSessionStatus.active,
        openedAt: DateTime(2026, 7, 29),
        revision: 1,
      );
      await repository.save(session);

      expect(await repository.findActiveByCourierId('courier-1'), isNotNull);

      await repository.save(session.copyWith(
        status: CourierSettlementSessionStatus.closed,
        revision: 2,
      ));

      expect(await repository.findActiveByCourierId('courier-1'), isNull);
    });

    test('findByCourierId returns only that courier\'s sessions, oldest first',
        () async {
      final repository = InMemoryCourierSettlementSessionRepository();
      await repository.save(CourierSettlementSession(
        id: 's1',
        courierId: 'courier-1',
        branchId: 'branch-1',
        status: CourierSettlementSessionStatus.closed,
        openedAt: DateTime(2026, 7, 28),
        revision: 1,
      ));
      await repository.save(CourierSettlementSession(
        id: 's2',
        courierId: 'courier-1',
        branchId: 'branch-1',
        status: CourierSettlementSessionStatus.active,
        openedAt: DateTime(2026, 7, 29),
        revision: 1,
      ));
      await repository.save(CourierSettlementSession(
        id: 's3',
        courierId: 'courier-2',
        branchId: 'branch-1',
        status: CourierSettlementSessionStatus.active,
        openedAt: DateTime(2026, 7, 29),
        revision: 1,
      ));

      final sessions = await repository.findByCourierId('courier-1');
      expect(sessions.map((s) => s.id), ['s1', 's2']);
    });
  });
}
