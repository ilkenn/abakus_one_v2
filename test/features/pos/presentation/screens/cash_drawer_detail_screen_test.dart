import 'package:abakus_one_v2/features/pos/data/cash_drawer_repository.dart';
import 'package:abakus_one_v2/features/pos/data/cash_movement_repository.dart';
import 'package:abakus_one_v2/features/pos/data/cash_session_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/cash/cash_drawer.dart';
import 'package:abakus_one_v2/features/pos/domain/cash/cash_session.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/cash_dependencies_provider.dart';
import 'package:abakus_one_v2/features/pos/presentation/screens/cash_drawer_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/cash_test_fixtures.dart';

void main() {
  Future<
      ({
        InMemoryCashDrawerRepository drawers,
        InMemoryCashSessionRepository sessions,
      })> pumpScreen(
    WidgetTester tester, {
    required CashDrawer drawer,
    CashSession? seedSession,
  }) async {
    final drawerRepository = InMemoryCashDrawerRepository();
    await drawerRepository.save(drawer);
    final sessionRepository = InMemoryCashSessionRepository();
    if (seedSession != null) {
      await sessionRepository.save(seedSession);
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cashDrawerRepositoryProvider.overrideWithValue(drawerRepository),
          cashSessionRepositoryProvider.overrideWithValue(sessionRepository),
          cashMovementRepositoryProvider
              .overrideWithValue(InMemoryCashMovementRepository()),
        ],
        child: MaterialApp(
          home: CashDrawerDetailScreen(drawerId: drawer.id),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (drawers: drawerRepository, sessions: sessionRepository);
  }

  const drawer =
      CashDrawer(id: 'drawer-1', branchId: 'branch-1', name: 'Ön Kasa');

  testWidgets('no active session shows the open-drawer action', (tester) async {
    await pumpScreen(tester, drawer: drawer);

    expect(find.text('Bu kasada aktif oturum yok'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Kasayı Aç'), findsOneWidget);
  });

  testWidgets('opening a drawer creates an active session', (tester) async {
    final repos = await pumpScreen(tester, drawer: drawer);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Kasayı Aç'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '500');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Kasayı Aç').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('Aktif oturum'), findsOneWidget);
    final active = await repos.sessions.findActiveByDrawerId(drawer.id);
    expect(active, isNotNull);
  });

  testWidgets('an existing active session offers to view it, not reopen',
      (tester) async {
    await pumpScreen(
      tester,
      drawer: drawer,
      seedSession: buildTestCashSession(
        sessionId: 'session-1',
        drawerId: drawer.id,
      ),
    );

    expect(find.text('Bu kasada aktif oturum yok'), findsNothing);
    expect(find.widgetWithText(ElevatedButton, 'Oturumu Görüntüle'),
        findsOneWidget);
  });
}
