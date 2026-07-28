import 'package:abakus_one_v2/features/pos/data/check_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/models/check.dart';
import 'package:abakus_one_v2/features/pos/domain/models/check_status.dart';
import 'package:flutter_test/flutter_test.dart';

Check _check({
  String id = 'check-1',
  String tableSessionId = 'tsession-1',
  int revision = 1,
  CheckStatus status = CheckStatus.open,
}) {
  return Check(
    id: id,
    tableSessionId: tableSessionId,
    branchId: 'branch-1',
    status: status,
    openedAt: DateTime(2026, 7, 29),
    revision: revision,
  );
}

void main() {
  test('findById returns the latest revision', () async {
    final repository = InMemoryCheckRepository();
    await repository.save(_check(revision: 1));
    await repository.save(_check(revision: 2, status: CheckStatus.submitted));

    final result = await repository.findById('check-1');

    expect(result!.revision, 2);
    expect(result.status, CheckStatus.submitted);
  });

  test(
      'findByTableSessionId returns the latest revision of every check under it',
      () async {
    final repository = InMemoryCheckRepository();
    await repository.save(_check(id: 'check-1', tableSessionId: 'tsession-1'));
    await repository.save(_check(id: 'check-2', tableSessionId: 'tsession-1'));
    await repository.save(_check(id: 'check-3', tableSessionId: 'tsession-2'));

    final results = await repository.findByTableSessionId('tsession-1');

    expect(results.map((c) => c.id).toSet(), {'check-1', 'check-2'});
  });
}
