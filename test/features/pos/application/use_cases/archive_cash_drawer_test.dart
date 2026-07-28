import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/pos/application/identity/cash_drawer_id_generator.dart';
import 'package:abakus_one_v2/features/pos/application/identity/cash_movement_id_generator.dart';
import 'package:abakus_one_v2/features/pos/application/identity/cash_session_id_generator.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/archive_cash_drawer.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/create_cash_drawer.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/open_cash_drawer.dart';
import 'package:abakus_one_v2/features/pos/data/cash_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/pos/data/cash_drawer_repository.dart';
import 'package:abakus_one_v2/features/pos/data/cash_movement_repository.dart';
import 'package:abakus_one_v2/features/pos/data/cash_session_repository.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_clock.dart';

void main() {
  test('archives a drawer with no active session', () async {
    final drawerRepository = InMemoryCashDrawerRepository();
    final sessionRepository = InMemoryCashSessionRepository();
    await CreateCashDrawer(
      idGenerator: SequentialCashDrawerIdGenerator(),
      repository: drawerRepository,
    )(branchId: 'branch-1', name: 'Kasa 1');
    final useCase = ArchiveCashDrawer(
      drawerRepository: drawerRepository,
      sessionRepository: sessionRepository,
    );

    final archived = await useCase('drawer-1');

    expect(archived.isActive, isFalse);
  });

  test('throws CashSessionAlreadyActiveViolation when a session is active',
      () async {
    final drawerRepository = InMemoryCashDrawerRepository();
    final sessionRepository = InMemoryCashSessionRepository();
    await CreateCashDrawer(
      idGenerator: SequentialCashDrawerIdGenerator(),
      repository: drawerRepository,
    )(branchId: 'branch-1', name: 'Kasa 1');
    await OpenCashDrawer(
      clock: FakeClock(DateTime(2026, 7, 29)),
      sessionIdGenerator: SequentialCashSessionIdGenerator(),
      movementIdGenerator: SequentialCashMovementIdGenerator(),
      drawerRepository: drawerRepository,
      sessionRepository: sessionRepository,
      movementRepository: InMemoryCashMovementRepository(),
      auditRepository: InMemoryCashAuditEntryRepository(),
    )(
      drawerId: 'drawer-1',
      openedByStaffId: 'staff-1',
      openingFloatAmount: Money.fromWhole(500, Currency.tryLira),
    );
    final useCase = ArchiveCashDrawer(
      drawerRepository: drawerRepository,
      sessionRepository: sessionRepository,
    );

    expect(
      () => useCase('drawer-1'),
      throwsA(isA<CashSessionAlreadyActiveViolation>()),
    );
  });
}
