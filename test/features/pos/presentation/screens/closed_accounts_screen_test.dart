import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/pos/data/order_closure_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/authorization_result.dart';
import 'package:abakus_one_v2/features/pos/domain/models/order_closure.dart';
import 'package:abakus_one_v2/features/pos/domain/models/order_closure_lifecycle_status.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/order_closure_dependencies_provider.dart';
import 'package:abakus_one_v2/features/pos/presentation/screens/closed_accounts_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_pos_authorization_policy.dart';

void main() {
  Future<InMemoryOrderClosureRepository> pumpScreen(
    WidgetTester tester, {
    required AuthorizationResult authorization,
    List<OrderClosure> seedRecords = const [],
  }) async {
    final repository = InMemoryOrderClosureRepository();
    for (final record in seedRecords) {
      await repository.save(record);
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          orderClosureRepositoryProvider.overrideWithValue(repository)
        ],
        child: MaterialApp(
          home: ClosedAccountsScreen(
            branchId: 'branch-1',
            authorizationPolicy: FakePosAuthorizationPolicy(authorization),
            viewerStaffId: 'staff-1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  testWidgets('shows a denial message when authorization is not granted',
      (tester) async {
    await pumpScreen(
      tester,
      authorization: const AuthorizationResult(
          granted: false, reason: 'Yönetici değilsiniz'),
    );

    expect(find.text('Yönetici değilsiniz'), findsOneWidget);
    expect(find.text('Kapatılmış hesap bulunamadı'), findsNothing);
  });

  testWidgets('lists closure records when authorized', (tester) async {
    await pumpScreen(
      tester,
      authorization: const AuthorizationResult(granted: true),
      seedRecords: [
        OrderClosure(
          closureId: 'c1',
          orderId: OrderId('order-1'),
          lifecycleStatus: OrderClosureLifecycleStatus.closed,
          closedByStaffId: 'staff-9',
          revision: 1,
        ),
      ],
    );

    expect(find.text('order-1'), findsOneWidget);
    expect(find.text('staff-9'), findsOneWidget);
  });

  testWidgets('an empty repository shows the empty-state view', (tester) async {
    await pumpScreen(tester,
        authorization: const AuthorizationResult(granted: true));

    expect(find.text('Kapatılmış hesap bulunamadı'), findsOneWidget);
  });

  testWidgets('filtering by status hides non-matching records', (tester) async {
    await pumpScreen(
      tester,
      authorization: const AuthorizationResult(granted: true),
      seedRecords: [
        OrderClosure(
          closureId: 'c1',
          orderId: OrderId('order-1'),
          lifecycleStatus: OrderClosureLifecycleStatus.closed,
          revision: 1,
        ),
        OrderClosure(
          closureId: 'c2',
          orderId: OrderId('order-2'),
          lifecycleStatus: OrderClosureLifecycleStatus.reopened,
          revision: 1,
        ),
      ],
    );

    expect(find.text('order-1'), findsOneWidget);
    expect(find.text('order-2'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'reopened'));
    await tester.pumpAndSettle();

    expect(find.text('order-1'), findsNothing);
    expect(find.text('order-2'), findsOneWidget);
  });
}
