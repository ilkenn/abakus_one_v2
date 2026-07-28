import 'package:abakus_one_v2/features/pos/data/cash_count_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/cash/cash_count.dart';
import 'package:abakus_one_v2/features/pos/domain/cash/cash_declaration.dart';
import 'package:abakus_one_v2/features/pos/domain/cash/cash_variance.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

CashCount _count({String id = 'count-1', String sessionId = 'session-1'}) {
  return CashCount(
    id: id,
    sessionId: sessionId,
    expectedAmount: Money.fromWhole(500, Currency.tryLira),
    declaration:
        CashDeclaration(actualAmount: Money.fromWhole(500, Currency.tryLira)),
    variance: CashVariance.compute(
      expectedAmount: Money.fromWhole(500, Currency.tryLira),
      actualAmount: Money.fromWhole(500, Currency.tryLira),
    ),
    declaredByStaffId: 'staff-1',
    declaredAt: DateTime(2026, 7, 29),
  );
}

void main() {
  test('append never overwrites — findBySessionId returns every count',
      () async {
    final repository = InMemoryCashCountRepository();
    await repository.append(_count(id: 'count-1'));
    await repository.append(_count(id: 'count-2'));

    final results = await repository.findBySessionId('session-1');

    expect(results.map((c) => c.id), ['count-1', 'count-2']);
  });

  test('findLatestBySessionId returns the most recently appended count',
      () async {
    final repository = InMemoryCashCountRepository();
    await repository.append(_count(id: 'count-1'));
    await repository.append(_count(id: 'count-2'));

    final latest = await repository.findLatestBySessionId('session-1');

    expect(latest!.id, 'count-2');
  });

  test('findLatestBySessionId returns null when no count has been submitted',
      () async {
    final repository = InMemoryCashCountRepository();
    expect(await repository.findLatestBySessionId('session-1'), isNull);
  });
}
