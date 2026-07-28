import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/transfer_check.dart';
import 'package:abakus_one_v2/features/pos/data/check_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/models/check.dart';
import 'package:abakus_one_v2/features/pos/domain/models/check_status.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/authorization_result.dart';
import 'package:abakus_one_v2/features/qr/data/table_session_repository.dart';
import 'package:abakus_one_v2/features/qr/domain/models/table_session.dart';
import 'package:abakus_one_v2/features/restaurant/data/restaurant_operations_audit_entry_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_clock.dart';
import '../../test_support/fake_pos_authorization_policy.dart';

TableSession _session(String id, {List<String> checkIds = const []}) {
  return TableSession(
    id: id,
    restaurantId: 'restaurant-1',
    branchId: 'branch-1',
    tableId: 'table-$id',
    status: TableSessionStatus.active,
    openedAt: DateTime(2026, 7, 29),
    guestSessionIds: const [],
    activeOrderIds: const [],
    checkIds: checkIds,
  );
}

void main() {
  test(
      'a pre-submission (open) check transfers without any authorization check',
      () async {
    final checkRepository = InMemoryCheckRepository();
    await checkRepository.save(Check(
      id: 'check-1',
      tableSessionId: 'tsession-a',
      branchId: 'branch-1',
      status: CheckStatus.open,
      openedAt: DateTime(2026, 7, 29),
      revision: 1,
    ));
    final tableSessionRepository = InMemoryTableSessionRepository();
    await tableSessionRepository
        .save(_session('tsession-a', checkIds: const ['check-1']));
    await tableSessionRepository.save(_session('tsession-b'));
    final policy =
        FakePosAuthorizationPolicy(const AuthorizationResult(granted: false));
    final useCase = TransferCheck(
      clock: FakeClock(DateTime(2026, 7, 29)),
      authorizationPolicy: policy,
      checkRepository: checkRepository,
      tableSessionRepository: tableSessionRepository,
      auditRepository: InMemoryRestaurantOperationsAuditEntryRepository(),
    );

    final result = await useCase(
      checkId: 'check-1',
      targetTableSessionId: 'tsession-b',
      performedByStaffId: 'staff-1',
    );

    expect(result.tableSessionId, 'tsession-b');
    expect(policy.callCount, 0);
    final source = await tableSessionRepository.findById('tsession-a');
    final target = await tableSessionRepository.findById('tsession-b');
    expect(source!.checkIds, isEmpty);
    expect(target!.checkIds, ['check-1']);
  });

  test('a submitted check requires authorization and logs an audit entry',
      () async {
    final checkRepository = InMemoryCheckRepository();
    await checkRepository.save(Check(
      id: 'check-1',
      tableSessionId: 'tsession-a',
      branchId: 'branch-1',
      status: CheckStatus.submitted,
      openedAt: DateTime(2026, 7, 29),
      revision: 2,
    ));
    final tableSessionRepository = InMemoryTableSessionRepository();
    await tableSessionRepository
        .save(_session('tsession-a', checkIds: const ['check-1']));
    await tableSessionRepository.save(_session('tsession-b'));
    final auditRepository = InMemoryRestaurantOperationsAuditEntryRepository();
    final useCase = TransferCheck(
      clock: FakeClock(DateTime(2026, 7, 29)),
      authorizationPolicy:
          FakePosAuthorizationPolicy(const AuthorizationResult(granted: true)),
      checkRepository: checkRepository,
      tableSessionRepository: tableSessionRepository,
      auditRepository: auditRepository,
    );

    await useCase(
      checkId: 'check-1',
      targetTableSessionId: 'tsession-b',
      performedByStaffId: 'staff-1',
    );

    final events = await auditRepository.findByBranchId('branch-1');
    expect(events, hasLength(1));
  });

  test('throws AuthorizationDeniedViolation when a submitted check is denied',
      () async {
    final checkRepository = InMemoryCheckRepository();
    await checkRepository.save(Check(
      id: 'check-1',
      tableSessionId: 'tsession-a',
      branchId: 'branch-1',
      status: CheckStatus.submitted,
      openedAt: DateTime(2026, 7, 29),
      revision: 2,
    ));
    final tableSessionRepository = InMemoryTableSessionRepository();
    await tableSessionRepository
        .save(_session('tsession-a', checkIds: const ['check-1']));
    await tableSessionRepository.save(_session('tsession-b'));
    final useCase = TransferCheck(
      clock: FakeClock(DateTime(2026, 7, 29)),
      authorizationPolicy:
          FakePosAuthorizationPolicy(const AuthorizationResult(granted: false)),
      checkRepository: checkRepository,
      tableSessionRepository: tableSessionRepository,
      auditRepository: InMemoryRestaurantOperationsAuditEntryRepository(),
    );

    expect(
      () => useCase(
        checkId: 'check-1',
        targetTableSessionId: 'tsession-b',
        performedByStaffId: 'staff-1',
      ),
      throwsA(isA<AuthorizationDeniedViolation>()),
    );
  });
}
