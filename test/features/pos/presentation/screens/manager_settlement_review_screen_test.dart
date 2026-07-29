import 'package:abakus_one_v2/features/pos/data/cash_movement_repository.dart';
import 'package:abakus_one_v2/features/pos/data/cash_session_repository.dart';
import 'package:abakus_one_v2/features/pos/data/courier_cash_declaration_repository.dart';
import 'package:abakus_one_v2/features/pos/data/courier_settlement_session_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/authorization_result.dart';
import 'package:abakus_one_v2/features/pos/domain/courier_settlement/courier_cash_declaration.dart';
import 'package:abakus_one_v2/features/pos/domain/courier_settlement/courier_settlement_session_status.dart';
import 'package:abakus_one_v2/features/pos/domain/courier_settlement/courier_settlement_variance.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/cash_dependencies_provider.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/courier_settlement_dependencies_provider.dart';
import 'package:abakus_one_v2/features/pos/presentation/screens/manager_settlement_review_screen.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/cash_test_fixtures.dart';
import '../../test_support/courier_settlement_test_fixtures.dart';
import '../../test_support/fake_pos_authorization_policy.dart';

void main() {
  Future<
      ({
        InMemoryCourierSettlementSessionRepository sessions,
        InMemoryCashMovementRepository movements,
      })> pumpScreen(
    WidgetTester tester, {
    AuthorizationResult? authorization,
  }) async {
    final sessionRepository = InMemoryCourierSettlementSessionRepository();
    await sessionRepository.save(buildTestCourierSettlementSession(
      status: CourierSettlementSessionStatus.pendingApproval,
    ));
    final declarationRepository = InMemoryCourierCashDeclarationRepository();
    await declarationRepository.append(CourierCashDeclaration(
      id: 'cdeclaration-1',
      settlementSessionId: 'csession-1',
      courierId: 'courier-1',
      expectedAmount: Money.fromWhole(200, Currency.tryLira),
      declaredAmount: Money.fromWhole(200, Currency.tryLira),
      variance: CourierSettlementVariance.compute(
        expectedAmount: Money.fromWhole(200, Currency.tryLira),
        declaredAmount: Money.fromWhole(200, Currency.tryLira),
      ),
      declaredAt: DateTime(2026, 7, 29, 22),
    ));

    final cashSessionRepository = InMemoryCashSessionRepository();
    await cashSessionRepository
        .save(buildTestCashSession(sessionId: 'drawer-session-1'));
    final cashMovementRepository = InMemoryCashMovementRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          courierSettlementSessionRepositoryProvider
              .overrideWithValue(sessionRepository),
          courierCashDeclarationRepositoryProvider
              .overrideWithValue(declarationRepository),
          cashSessionRepositoryProvider
              .overrideWithValue(cashSessionRepository),
          cashMovementRepositoryProvider
              .overrideWithValue(cashMovementRepository),
        ],
        child: MaterialApp(
          home: ManagerSettlementReviewScreen(
            settlementSessionId: 'csession-1',
            authorizationPolicy: authorization == null
                ? null
                : FakePosAuthorizationPolicy(authorization),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (sessions: sessionRepository, movements: cashMovementRepository);
  }

  testWidgets('shows expected/declared/variance for the latest declaration',
      (tester) async {
    await pumpScreen(tester,
        authorization: const AuthorizationResult(granted: true));

    expect(find.text('Beklenen: 200.00'), findsOneWidget);
    expect(find.text('Bildirilen: 200.00'), findsOneWidget);
  });

  testWidgets('approving requires a target cash session id', (tester) async {
    await pumpScreen(tester,
        authorization: const AuthorizationResult(granted: true));

    await tester.tap(find.widgetWithText(ElevatedButton, 'Onayla'));
    await tester.pumpAndSettle();

    expect(find.text('Hedef kasa oturumu girin.'), findsOneWidget);
  });

  testWidgets(
      'approving with a target session records the CashMovement and '
      'offers to close', (tester) async {
    final repos = await pumpScreen(tester,
        authorization: const AuthorizationResult(granted: true));

    await tester.enterText(
        find.widgetWithText(TextField, 'Hedef Kasa Oturumu No'),
        'drawer-session-1');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Onayla'));
    await tester.pumpAndSettle();

    final session = await repos.sessions.findById('csession-1');
    expect(session!.status, CourierSettlementSessionStatus.approved);
    final movements = await repos.movements.findBySessionId('drawer-session-1');
    expect(movements, hasLength(1));
    expect(
        find.widgetWithText(ElevatedButton, 'Oturumu Kapat'), findsOneWidget);
  });

  testWidgets('rejecting moves the session to rejected', (tester) async {
    final repos = await pumpScreen(tester,
        authorization: const AuthorizationResult(granted: true));

    await tester.tap(find.widgetWithText(OutlinedButton, 'Reddet'));
    await tester.pumpAndSettle();

    final session = await repos.sessions.findById('csession-1');
    expect(session!.status, CourierSettlementSessionStatus.rejected);
  });
}
