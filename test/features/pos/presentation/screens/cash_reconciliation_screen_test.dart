import 'package:abakus_one_v2/features/pos/data/cash_count_repository.dart';
import 'package:abakus_one_v2/features/pos/data/cash_movement_repository.dart';
import 'package:abakus_one_v2/features/pos/data/cash_reconciliation_repository.dart';
import 'package:abakus_one_v2/features/pos/data/cash_session_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/authorization_result.dart';
import 'package:abakus_one_v2/features/pos/domain/cash/cash_session_status.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/cash_dependencies_provider.dart';
import 'package:abakus_one_v2/features/pos/presentation/screens/cash_reconciliation_screen.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/cash_test_fixtures.dart';
import '../../test_support/fake_pos_authorization_policy.dart';

void main() {
  Future<InMemoryCashSessionRepository> pumpScreen(
    WidgetTester tester, {
    AuthorizationResult? authorization,
  }) async {
    final sessionRepository = InMemoryCashSessionRepository();
    await sessionRepository.save(buildTestCashSession(sessionId: 'session-1'));
    final countRepository = InMemoryCashCountRepository();
    final reconciliationRepository = InMemoryCashReconciliationRepository();

    await submitTestCashCount(
      sessionRepository: sessionRepository,
      movementRepository: InMemoryCashMovementRepository(),
      countRepository: countRepository,
      sessionId: 'session-1',
      actualAmount: Money.fromWhole(500, Currency.tryLira),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cashSessionRepositoryProvider.overrideWithValue(sessionRepository),
          cashCountRepositoryProvider.overrideWithValue(countRepository),
          cashReconciliationRepositoryProvider
              .overrideWithValue(reconciliationRepository),
        ],
        child: MaterialApp(
          home: CashReconciliationScreen(
            sessionId: 'session-1',
            authorizationPolicy: authorization == null
                ? null
                : FakePosAuthorizationPolicy(authorization),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return sessionRepository;
  }

  testWidgets('shows expected/actual/variance for the latest count',
      (tester) async {
    await pumpScreen(tester,
        authorization: const AuthorizationResult(granted: true));

    expect(find.text('Beklenen: 0.00'), findsOneWidget);
    expect(find.text('Sayılan: 500.00'), findsOneWidget);
  });

  testWidgets('without an authorization policy, approving surfaces a message',
      (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Onayla'));
    await tester.pumpAndSettle();

    expect(find.text('Yetki politikası tanımlı değil.'), findsOneWidget);
  });

  testWidgets('approving moves the session to approved and offers to close',
      (tester) async {
    final sessionRepository = await pumpScreen(tester,
        authorization: const AuthorizationResult(granted: true));

    await tester.tap(find.widgetWithText(ElevatedButton, 'Onayla'));
    await tester.pumpAndSettle();

    final session = await sessionRepository.findById('session-1');
    expect(session!.status, CashSessionStatus.approved);
    expect(
        find.widgetWithText(ElevatedButton, 'Oturumu Kapat'), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Oturumu Kapat'));
    await tester.pumpAndSettle();

    final closed = await sessionRepository.findById('session-1');
    expect(closed!.status, CashSessionStatus.closed);
  });

  testWidgets('rejecting moves the session to rejected', (tester) async {
    final sessionRepository = await pumpScreen(tester,
        authorization: const AuthorizationResult(granted: true));

    await tester.tap(find.widgetWithText(OutlinedButton, 'Reddet'));
    await tester.pumpAndSettle();

    final session = await sessionRepository.findById('session-1');
    expect(session!.status, CashSessionStatus.rejected);
  });
}
