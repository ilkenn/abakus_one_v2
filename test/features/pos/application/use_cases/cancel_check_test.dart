import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/cancel_check.dart';
import 'package:abakus_one_v2/features/pos/data/check_repository.dart';
import 'package:abakus_one_v2/features/pos/data/pos_order_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/models/check.dart';
import 'package:abakus_one_v2/features/pos/domain/models/check_status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/pos_test_fixtures.dart';

void main() {
  test('cancels an open check and discards its draft', () async {
    final checkRepository = InMemoryCheckRepository();
    final posOrderRepository = InMemoryPosOrderRepository();
    await posOrderRepository.saveDraft(
        'check-1-session', buildTestSession(sessionId: 'check-1-session'));
    final check = Check(
      id: 'check-1',
      tableSessionId: 'tsession-1',
      branchId: 'branch-1',
      status: CheckStatus.open,
      posOrderSessionId: 'check-1-session',
      openedAt: DateTime(2026, 7, 29),
      revision: 1,
    );
    await checkRepository.save(check);

    final useCase = CancelCheck(
      checkRepository: checkRepository,
      posOrderRepository: posOrderRepository,
    );
    final result = await useCase(check);

    expect(result.status, CheckStatus.cancelled);
    expect(await posOrderRepository.getDraft('check-1-session'), isNull);
  });

  test('throws CheckNotOpenViolation for an already-submitted check', () async {
    final check = Check(
      id: 'check-1',
      tableSessionId: 'tsession-1',
      branchId: 'branch-1',
      status: CheckStatus.submitted,
      openedAt: DateTime(2026, 7, 29),
      revision: 2,
    );
    final useCase = CancelCheck(
      checkRepository: InMemoryCheckRepository(),
      posOrderRepository: InMemoryPosOrderRepository(),
    );

    expect(() => useCase(check), throwsA(isA<CheckNotOpenViolation>()));
  });
}
