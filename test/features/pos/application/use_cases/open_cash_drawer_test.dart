import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/pos/application/identity/cash_movement_id_generator.dart';
import 'package:abakus_one_v2/features/pos/application/identity/cash_session_id_generator.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/create_cash_drawer.dart';
import 'package:abakus_one_v2/features/pos/application/identity/cash_drawer_id_generator.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/open_cash_drawer.dart';
import 'package:abakus_one_v2/features/pos/data/cash_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/pos/data/cash_drawer_repository.dart';
import 'package:abakus_one_v2/features/pos/data/cash_movement_repository.dart';
import 'package:abakus_one_v2/features/pos/data/cash_session_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/cash/cash_audit_event_type.dart';
import 'package:abakus_one_v2/features/pos/domain/cash/cash_movement_type.dart';
import 'package:abakus_one_v2/features/pos/domain/cash/cash_session_status.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_clock.dart';

void main() {
  late CashDrawerRepository drawerRepository;
  late CashSessionRepository sessionRepository;
  late CashMovementRepository movementRepository;
  late CashAuditEntryRepository auditRepository;
  late OpenCashDrawer useCase;

  setUp(() async {
    drawerRepository = InMemoryCashDrawerRepository();
    sessionRepository = InMemoryCashSessionRepository();
    movementRepository = InMemoryCashMovementRepository();
    auditRepository = InMemoryCashAuditEntryRepository();
    useCase = OpenCashDrawer(
      clock: FakeClock(DateTime(2026, 7, 29, 9)),
      sessionIdGenerator: SequentialCashSessionIdGenerator(),
      movementIdGenerator: SequentialCashMovementIdGenerator(),
      drawerRepository: drawerRepository,
      sessionRepository: sessionRepository,
      movementRepository: movementRepository,
      auditRepository: auditRepository,
    );
    await CreateCashDrawer(
      idGenerator: SequentialCashDrawerIdGenerator(prefix: 'drawer'),
      repository: drawerRepository,
    )(branchId: 'branch-1', name: 'Kasa 1');
  });

  test(
      'opens a new active session, records the opening-float movement, and logs an audit entry',
      () async {
    final session = await useCase(
      drawerId: 'drawer-1',
      openedByStaffId: 'staff-1',
      openingFloatAmount: Money.fromWhole(500, Currency.tryLira),
    );

    expect(session.status, CashSessionStatus.active);
    expect(session.opening.openingFloatAmount,
        Money.fromWhole(500, Currency.tryLira));

    final movements = await movementRepository.findBySessionId(session.id);
    expect(movements, hasLength(1));
    expect(movements.single.type, CashMovementType.openingFloat);
    expect(movements.single.amount, Money.fromWhole(500, Currency.tryLira));

    final events = await auditRepository.findByDrawerId('drawer-1');
    expect(events.single.type, CashAuditEventType.drawerOpened);
  });

  test(
      'throws CashSessionAlreadyActiveViolation for a second open while one is active',
      () async {
    await useCase(
      drawerId: 'drawer-1',
      openedByStaffId: 'staff-1',
      openingFloatAmount: Money.fromWhole(500, Currency.tryLira),
    );

    expect(
      () => useCase(
        drawerId: 'drawer-1',
        openedByStaffId: 'staff-2',
        openingFloatAmount: Money.fromWhole(500, Currency.tryLira),
      ),
      throwsA(isA<CashSessionAlreadyActiveViolation>()),
    );
  });

  test('throws UnknownCashEntityViolation for an unknown drawer', () async {
    expect(
      () => useCase(
        drawerId: 'missing',
        openedByStaffId: 'staff-1',
        openingFloatAmount: Money.fromWhole(500, Currency.tryLira),
      ),
      throwsA(isA<UnknownCashEntityViolation>()),
    );
  });
}
