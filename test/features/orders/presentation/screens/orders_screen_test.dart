import 'dart:async';

import 'package:abakus_one_v2/features/auth/domain/models/auth_session.dart';
import 'package:abakus_one_v2/features/auth/presentation/providers/auth_provider.dart';
import 'package:abakus_one_v2/features/orders/data/canonical_order_repository.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_line.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_number.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_status.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_timestamps.dart';
import 'package:abakus_one_v2/features/orders/domain/pricing/price_calculator.dart';
import 'package:abakus_one_v2/features/orders/domain/pricing/tax_policy.dart';
import 'package:abakus_one_v2/features/orders/presentation/providers/orders_provider.dart';
import 'package:abakus_one_v2/features/orders/presentation/screens/orders_screen.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:abakus_one_v2/shared/widgets/feedback/error_view.dart';
import 'package:abakus_one_v2/shared/widgets/feedback/loading_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _SignedInNotifier extends AuthNotifier {
  @override
  AuthState build() => AuthState(
        isAuthenticated: true,
        isGuest: false,
        session: AuthSession(
          uid: 'uid-1',
          phoneNumber: '+905321234567',
          createdAt: DateTime(2026, 1, 1),
          expiresAt: DateTime(2026, 12, 31),
        ),
      );
}

/// Never resolves — used to assert the loading state renders [LoadingView].
class _PendingCanonicalOrderRepository implements CanonicalOrderRepository {
  @override
  Future<Order> submitOrder(Order order) async => order;

  @override
  Future<Order?> findById(OrderId orderId) async => null;

  @override
  Future<List<Order>> findByCustomerId(String customerId) =>
      Completer<List<Order>>().future;

  @override
  Future<List<Order>> findAll() async => [];
}

/// Always throws — used to assert the error state renders [ErrorView].
class _FailingCanonicalOrderRepository implements CanonicalOrderRepository {
  @override
  Future<Order> submitOrder(Order order) async => order;

  @override
  Future<Order?> findById(OrderId orderId) async => null;

  @override
  Future<List<Order>> findByCustomerId(String customerId) async {
    throw StateError('network error');
  }

  @override
  Future<List<Order>> findAll() async => [];
}

Future<void> _pumpOrdersScreen(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: OrdersScreen()),
    ),
  );
}

void main() {
  testWidgets('shows LoadingView while the canonical fetch is pending',
      (tester) async {
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(() => _SignedInNotifier()),
        canonicalOrderRepositoryProvider
            .overrideWithValue(_PendingCanonicalOrderRepository()),
      ],
    );
    addTearDown(container.dispose);

    await _pumpOrdersScreen(tester, container);
    await tester.pump();

    expect(find.byType(LoadingView), findsOneWidget);
  });

  testWidgets('shows ErrorView with a retry action when the fetch fails',
      (tester) async {
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(() => _SignedInNotifier()),
        canonicalOrderRepositoryProvider
            .overrideWithValue(_FailingCanonicalOrderRepository()),
      ],
    );
    addTearDown(container.dispose);

    await _pumpOrdersScreen(tester, container);
    await tester.pumpAndSettle();

    expect(find.byType(ErrorView), findsOneWidget);
    expect(find.text('Tekrar Dene'), findsOneWidget);
  });

  testWidgets(
      'shows the real empty state for a signed-in customer with no '
      'orders yet', (tester) async {
    final container = ProviderContainer(
      overrides: [authProvider.overrideWith(() => _SignedInNotifier())],
    );
    addTearDown(container.dispose);

    await _pumpOrdersScreen(tester, container);
    await tester.pumpAndSettle();

    expect(find.text('Henüz bir siparişiniz bulunmuyor.'), findsOneWidget);
  });

  testWidgets('shows a real canonical order once loaded', (tester) async {
    final container = ProviderContainer(
      overrides: [authProvider.overrideWith(() => _SignedInNotifier())],
    );
    addTearDown(container.dispose);
    final line = OrderLine.create(
      productId: 'p1',
      productName: 'Mexifit Bowl',
      quantity: 1,
      unitPrice: Money.fromWhole(194, Currency.tryLira),
      taxRate: TaxPolicy.defaultRate,
    );
    await container.read(canonicalOrderRepositoryProvider).submitOrder(Order(
          id: OrderId('order-1'),
          orderNumber: OrderNumber('A-1'),
          status: OrderStatus.pendingConfirmation,
          channel: OrderChannel.delivery,
          branchId: 'branch-1',
          restaurantId: 'restaurant-1',
          customerId: 'uid-1',
          lines: [line],
          pricing: PriceCalculator.calculate(
            lines: [line],
            currency: Currency.tryLira,
          ),
          timestamps: OrderTimestamps(created: DateTime(2026, 7, 1)),
        ));

    await _pumpOrdersScreen(tester, container);
    await tester.pumpAndSettle();

    expect(find.text('order-1'), findsOneWidget);
    expect(find.text('Onay Bekliyor'), findsOneWidget);
  });
}
