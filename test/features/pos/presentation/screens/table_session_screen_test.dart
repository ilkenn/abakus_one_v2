import 'package:abakus_one_v2/core/utils/clock_provider.dart';
import 'package:abakus_one_v2/features/orders/domain/identity/order_identity.dart';
import 'package:abakus_one_v2/features/orders/presentation/providers/order_identity_provider.dart';
import 'package:abakus_one_v2/features/pos/data/check_repository.dart';
import 'package:abakus_one_v2/features/pos/data/pos_order_repository.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/check_dependencies_provider.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/pos_dependencies_provider.dart';
import 'package:abakus_one_v2/features/pos/presentation/screens/table_session_screen.dart';
import 'package:abakus_one_v2/features/qr/data/table_session_repository.dart';
import 'package:abakus_one_v2/features/qr/domain/models/table_session.dart';
import 'package:abakus_one_v2/features/qr/presentation/providers/table_session_dependencies_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_clock.dart';

void main() {
  Future<
      ({
        InMemoryTableSessionRepository tableSessionRepository,
        InMemoryCheckRepository checkRepository,
      })> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final tableSessionRepository = InMemoryTableSessionRepository();
    await tableSessionRepository.save(TableSession(
      id: 'tsession-1',
      restaurantId: 'restaurant-1',
      branchId: 'branch-1',
      tableId: 'table-1',
      status: TableSessionStatus.active,
      openedAt: DateTime(2026, 7, 29),
      guestSessionIds: const [],
      activeOrderIds: const [],
    ));
    final checkRepository = InMemoryCheckRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clockProvider.overrideWithValue(FakeClock(DateTime(2026, 7, 29))),
          tableSessionRepositoryProvider
              .overrideWithValue(tableSessionRepository),
          checkRepositoryProvider.overrideWithValue(checkRepository),
          posOrderRepositoryProvider
              .overrideWithValue(InMemoryPosOrderRepository()),
          orderIdentityProvider
              .overrideWithValue(InMemoryOrderIdentityProvider()),
        ],
        child: const MaterialApp(
          home: TableSessionScreen(
            tableSessionId: 'tsession-1',
            restaurantId: 'restaurant-abakus',
            staffId: 'staff-1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (
      tableSessionRepository: tableSessionRepository,
      checkRepository: checkRepository,
    );
  }

  testWidgets('opening a new check shows it in the list', (tester) async {
    final repos = await pumpScreen(tester);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    final checks =
        await repos.checkRepository.findByTableSessionId('tsession-1');
    expect(checks, hasLength(1));
    expect(find.text(checks.first.id), findsOneWidget);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('cancelling an open check removes its actions', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'İptal Et'));
    await tester.pumpAndSettle();

    expect(find.text('cancelled'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'İptal Et'), findsNothing);
  });
}
