import 'package:abakus_one_v2/core/utils/clock_provider.dart';
import 'package:abakus_one_v2/features/cart/domain/models/cart_item.dart';
import 'package:abakus_one_v2/features/orders/domain/mappers/cart_to_order_mapper.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_number.dart';
import 'package:abakus_one_v2/features/pos/data/closure_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/pos/data/order_closure_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/authorization_result.dart';
import 'package:abakus_one_v2/features/pos/domain/models/order_closure.dart';
import 'package:abakus_one_v2/features/pos/domain/models/order_closure_lifecycle_status.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/order_closure_dependencies_provider.dart';
import 'package:abakus_one_v2/features/pos/presentation/screens/closed_account_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_clock.dart';
import '../../test_support/fake_pos_authorization_policy.dart';

Order _buildOrder() {
  return CartToOrderMapper.map(
    orderId: OrderId('order-1'),
    orderNumber: OrderNumber('A-001'),
    cartItems: const [
      CartItem(id: 'p1', name: 'Mexifit Bowl', desc: '', price: 194.0, quantity: 1),
    ],
    channel: OrderChannel.dineInStaff,
    branchId: 'branch-1',
    restaurantId: 'restaurant-abakus',
    now: DateTime(2026, 7, 29),
  );
}

void main() {
  Future<
      ({
        InMemoryOrderClosureRepository closureRepository,
        InMemoryClosureAuditEntryRepository auditRepository,
      })> pumpScreen(
    WidgetTester tester, {
    required AuthorizationResult authorization,
  }) async {
    final closureRepository = InMemoryOrderClosureRepository();
    final auditRepository = InMemoryClosureAuditEntryRepository();
    await closureRepository.save(
      OrderClosure(
        closureId: 'c1',
        orderId: OrderId('order-1'),
        lifecycleStatus: OrderClosureLifecycleStatus.closed,
        closedByStaffId: 'staff-9',
        revision: 1,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          orderClosureRepositoryProvider.overrideWithValue(closureRepository),
          closureAuditEntryRepositoryProvider.overrideWithValue(auditRepository),
          clockProvider.overrideWithValue(FakeClock(DateTime(2026, 7, 29, 12, 0))),
        ],
        child: MaterialApp(
          home: ClosedAccountDetailScreen(
            closureId: 'c1',
            order: _buildOrder(),
            authorizationPolicy: FakePosAuthorizationPolicy(authorization),
            viewerStaffId: 'staff-1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (closureRepository: closureRepository, auditRepository: auditRepository);
  }

  testWidgets('shows a denial message when authorization is not granted', (tester) async {
    await pumpScreen(
      tester,
      authorization: const AuthorizationResult(granted: false, reason: 'Yetkiniz yok'),
    );

    expect(find.text('Yetkiniz yok'), findsOneWidget);
  });

  testWidgets('shows closure status and metadata when authorized', (tester) async {
    await pumpScreen(tester, authorization: const AuthorizationResult(granted: true));

    expect(find.textContaining('Durum: closed'), findsOneWidget);
    expect(find.textContaining('Kapatan: staff-9'), findsOneWidget);
    expect(find.textContaining('Yeniden açma sayısı: 0'), findsOneWidget);
  });

  testWidgets('reopening via the dialog updates status and logs an audit entry', (tester) async {
    final repos = await pumpScreen(tester, authorization: const AuthorizationResult(granted: true));

    await tester.tap(find.widgetWithText(OutlinedButton, 'Yeniden Aç'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Müşteri itirazı');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Onayla'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Durum: reopened'), findsOneWidget);
    final events = await repos.auditRepository.findByOrderId(OrderId('order-1'));
    expect(events, isNotEmpty);
  });

  testWidgets('requesting a duplicate receipt shows the print result and logs an audit entry', (tester) async {
    final repos = await pumpScreen(tester, authorization: const AuthorizationResult(granted: true));

    await tester.tap(find.widgetWithText(OutlinedButton, 'Fiş Tekrar Yazdır'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Fiş yazdırma:'), findsOneWidget);
    final events = await repos.auditRepository.findByOrderId(OrderId('order-1'));
    expect(events, isNotEmpty);
  });
}
