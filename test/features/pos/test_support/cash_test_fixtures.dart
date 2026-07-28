import 'package:abakus_one_v2/features/pos/application/identity/cash_count_id_generator.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/submit_cash_count.dart';
import 'package:abakus_one_v2/features/pos/data/cash_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/pos/data/cash_count_repository.dart';
import 'package:abakus_one_v2/features/pos/data/cash_movement_repository.dart';
import 'package:abakus_one_v2/features/pos/data/cash_session_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/cash/cash_count.dart';
import 'package:abakus_one_v2/features/pos/domain/cash/cash_opening.dart';
import 'package:abakus_one_v2/features/pos/domain/cash/cash_session.dart';
import 'package:abakus_one_v2/features/pos/domain/cash/cash_session_status.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';

import 'fake_clock.dart';

/// A minimal, valid, active [CashSession] for use-case tests that need a
/// starting point rather than exercising `OpenCashDrawer` itself.
CashSession buildTestCashSession({
  String sessionId = 'session-1',
  String drawerId = 'drawer-1',
  CashSessionStatus status = CashSessionStatus.active,
  int revision = 1,
  Money? openingFloatAmount,
}) {
  return CashSession(
    id: sessionId,
    drawerId: drawerId,
    branchId: 'branch-1',
    status: status,
    opening: CashOpening(
      openedByStaffId: 'staff-1',
      openedAt: DateTime(2026, 7, 29, 9),
      openingFloatAmount:
          openingFloatAmount ?? Money.fromWhole(500, Currency.tryLira),
    ),
    revision: revision,
  );
}

/// Seeds a `session` (active) with a single submitted [CashCount] via the
/// real `SubmitCashCount` use case — used by
/// `ApproveCashReconciliation`/`RejectCashReconciliation`/
/// `CloseCashSession` tests that need a session already sitting at
/// `pendingApproval`.
Future<CashCount> submitTestCashCount({
  required CashSessionRepository sessionRepository,
  required CashMovementRepository movementRepository,
  required CashCountRepository countRepository,
  required String sessionId,
  required Money actualAmount,
  String declaredByStaffId = 'staff-1',
}) {
  return SubmitCashCount(
    clock: FakeClock(DateTime(2026, 7, 29, 22)),
    idGenerator: SequentialCashCountIdGenerator(),
    sessionRepository: sessionRepository,
    movementRepository: movementRepository,
    countRepository: countRepository,
    auditRepository: InMemoryCashAuditEntryRepository(),
  )(
    sessionId: sessionId,
    actualAmount: actualAmount,
    declaredByStaffId: declaredByStaffId,
  );
}
