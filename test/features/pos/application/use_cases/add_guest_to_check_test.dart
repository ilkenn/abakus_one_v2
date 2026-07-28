import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/add_guest_to_check.dart';
import 'package:abakus_one_v2/features/pos/data/check_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/models/check.dart';
import 'package:abakus_one_v2/features/pos/domain/models/check_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('adds a guest and bumps the revision', () async {
    final repository = InMemoryCheckRepository();
    await repository.save(Check(
      id: 'check-1',
      tableSessionId: 'tsession-1',
      branchId: 'branch-1',
      status: CheckStatus.open,
      openedAt: DateTime(2026, 7, 29),
      revision: 1,
    ));
    final useCase = AddGuestToCheck(repository: repository);

    final result = await useCase(checkId: 'check-1', guestSessionId: 'guest-1');

    expect(result.guestSessionIds, ['guest-1']);
    expect(result.revision, 2);
  });

  test('throws UnknownRestaurantOperationsEntityViolation for an unknown check',
      () async {
    final useCase = AddGuestToCheck(repository: InMemoryCheckRepository());

    expect(
      () => useCase(checkId: 'missing', guestSessionId: 'guest-1'),
      throwsA(isA<UnknownRestaurantOperationsEntityViolation>()),
    );
  });
}
