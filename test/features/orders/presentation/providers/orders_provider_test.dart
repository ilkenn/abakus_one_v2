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
import 'package:abakus_one_v2/features/orders/domain/models/order_model.dart';
import 'package:abakus_one_v2/features/orders/presentation/providers/orders_provider.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _SignedInNotifier extends AuthNotifier {
  _SignedInNotifier(this.uid);
  final String uid;

  @override
  AuthState build() => AuthState(
        isAuthenticated: true,
        isGuest: false,
        session: AuthSession(
          uid: uid,
          phoneNumber: '+905321234567',
          createdAt: DateTime(2026, 1, 1),
          expiresAt: DateTime(2026, 12, 31),
        ),
      );
}

class _SignedOutNotifier extends AuthNotifier {
  @override
  AuthState build() => const AuthState(isAuthenticated: false, isGuest: false);
}

/// A [CanonicalOrderRepository] whose [findByCustomerId] only resolves once
/// [release] is called — used to prove a mutator called while the initial
/// load is still in flight does not get clobbered once that load resolves.
class _SlowCanonicalOrderRepository implements CanonicalOrderRepository {
  _SlowCanonicalOrderRepository(this._orders);
  final List<Order> _orders;
  final Completer<void> _gate = Completer<void>();

  void release() => _gate.complete();

  @override
  Future<Order> submitOrder(Order order) async => order;

  @override
  Future<Order?> findById(OrderId orderId) async => null;

  @override
  Future<List<Order>> findByCustomerId(String customerId) async {
    await _gate.future;
    return _orders.where((o) => o.customerId == customerId).toList();
  }

  @override
  Future<List<Order>> findAll() async => _orders;
}

Order _buildOrder({
  required String id,
  required String customerId,
  OrderStatus status = OrderStatus.pendingConfirmation,
  DateTime? created,
  String productName = 'Mexifit Bowl',
}) {
  final line = OrderLine.create(
    productId: 'p1',
    productName: productName,
    quantity: 1,
    unitPrice: Money.fromWhole(194, Currency.tryLira),
    taxRate: TaxPolicy.defaultRate,
  );
  return Order(
    id: OrderId(id),
    orderNumber: OrderNumber('A-$id'),
    status: status,
    channel: OrderChannel.delivery,
    branchId: 'branch-1',
    restaurantId: 'restaurant-1',
    customerId: customerId,
    lines: [line],
    pricing: PriceCalculator.calculate(
      lines: [line],
      currency: Currency.tryLira,
    ),
    timestamps: OrderTimestamps(created: created ?? DateTime(2026, 7, 1)),
  );
}

void main() {
  group('OrdersNotifier.build (Phase 9K, docs/decisions.md ADR-026)', () {
    test(
        'returns an empty list when signed out — never falls back to the '
        'legacy LocalOrdersRepository seed', () async {
      final container = ProviderContainer(
        overrides: [authProvider.overrideWith(() => _SignedOutNotifier())],
      );
      addTearDown(container.dispose);

      final orders = await container.read(ordersProvider.future);

      expect(orders, isEmpty);
    });

    test(
        'a new customer with no orders sees an empty history, not a crash '
        'or stale demo data', () async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(() => _SignedInNotifier('uid-new'))
        ],
      );
      addTearDown(container.dispose);

      final orders = await container.read(ordersProvider.future);

      expect(orders, isEmpty);
    });

    test(
        'returns only the signed-in customer\'s own orders, never another '
        'customer\'s — IDOR-equivalent check at the provider layer, '
        'complementing the firestore.rules adversarial test', () async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(() => _SignedInNotifier('uid-1'))
        ],
      );
      addTearDown(container.dispose);
      final repository = container.read(canonicalOrderRepositoryProvider);
      await repository.submitOrder(
        _buildOrder(id: 'order-1', customerId: 'uid-1'),
      );
      await repository.submitOrder(
        _buildOrder(id: 'order-2', customerId: 'uid-2'),
      );

      final orders = await container.read(ordersProvider.future);

      expect(orders.map((o) => o.id), ['order-1']);
    });

    test('orders are newest-first by creation timestamp', () async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(() => _SignedInNotifier('uid-1'))
        ],
      );
      addTearDown(container.dispose);
      final repository = container.read(canonicalOrderRepositoryProvider);
      await repository.submitOrder(_buildOrder(
        id: 'order-older',
        customerId: 'uid-1',
        created: DateTime(2026, 7, 1),
      ));
      await repository.submitOrder(_buildOrder(
        id: 'order-newer',
        customerId: 'uid-1',
        created: DateTime(2026, 7, 15),
      ));

      final orders = await container.read(ordersProvider.future);

      expect(orders.map((o) => o.id), ['order-newer', 'order-older']);
    });

    test('a completed order round-trips to the legacy "Teslim Edildi" label',
        () async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(() => _SignedInNotifier('uid-1'))
        ],
      );
      addTearDown(container.dispose);
      await container.read(canonicalOrderRepositoryProvider).submitOrder(
            _buildOrder(
              id: 'order-1',
              customerId: 'uid-1',
              status: OrderStatus.completed,
            ),
          );

      final orders = await container.read(ordersProvider.future);

      expect(orders.single.status, 'Teslim Edildi');
      expect(orders.single.lifecycleStatus, OrderStatus.completed);
    });

    test('a cancelled order round-trips to the legacy "İptal Edildi" label',
        () async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(() => _SignedInNotifier('uid-1'))
        ],
      );
      addTearDown(container.dispose);
      await container.read(canonicalOrderRepositoryProvider).submitOrder(
            _buildOrder(
              id: 'order-1',
              customerId: 'uid-1',
              status: OrderStatus.cancelled,
            ),
          );

      final orders = await container.read(ordersProvider.future);

      expect(orders.single.status, 'İptal Edildi');
      expect(orders.single.lifecycleStatus, OrderStatus.cancelled);
    });
  });

  group('OrdersNotifier.addOrder', () {
    test('prepends a just-submitted order to the resolved list', () async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(() => _SignedInNotifier('uid-1'))
        ],
      );
      addTearDown(container.dispose);
      await container.read(ordersProvider.future);

      await container.read(ordersProvider.notifier).addOrder(
            const OrderModel(
              id: 'order-bridge',
              date: '01.08.2026',
              totalAmount: 100,
              status: 'Onay Bekliyor',
            ),
          );

      final orders = container.read(ordersProvider).value;
      expect(orders, isNotNull);
      expect(orders!.first.id, 'order-bridge');
    });

    test(
        'a still-in-flight initial load can never clobber addOrder — the '
        'mutation survives once the slow load resolves', () async {
      final slowRepository = _SlowCanonicalOrderRepository([]);
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(() => _SignedInNotifier('uid-1')),
          canonicalOrderRepositoryProvider.overrideWithValue(slowRepository),
        ],
      );
      addTearDown(container.dispose);

      // Start the (slow) initial load, but do not await it yet.
      final initialLoad = container.read(ordersProvider.future);

      // A checkout completes and bridges its order in while the initial
      // load is still pending.
      final addOrderCall = container.read(ordersProvider.notifier).addOrder(
            const OrderModel(
              id: 'order-bridge',
              date: '01.08.2026',
              totalAmount: 100,
              status: 'Onay Bekliyor',
            ),
          );

      // Now let the slow initial load resolve.
      slowRepository.release();
      await initialLoad;
      await addOrderCall;

      final orders = container.read(ordersProvider).value;
      expect(orders, isNotNull);
      expect(orders!.map((o) => o.id), ['order-bridge']);
    });
  });

  group(
      'OrdersNotifier.cancelOrder / submitReview (unchanged, session-local '
      'mutations — never persisted, matching the pre-Phase-9K behavior)', () {
    test(
        'cancelOrder transitions a cancellable order and leaves others '
        'unchanged', () async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(() => _SignedInNotifier('uid-1'))
        ],
      );
      addTearDown(container.dispose);
      final repository = container.read(canonicalOrderRepositoryProvider);
      await repository.submitOrder(_buildOrder(
        id: 'order-1',
        customerId: 'uid-1',
        status: OrderStatus.pendingConfirmation,
      ));
      await repository.submitOrder(_buildOrder(
        id: 'order-2',
        customerId: 'uid-1',
        status: OrderStatus.pendingConfirmation,
        created: DateTime(2026, 6, 1),
      ));
      await container.read(ordersProvider.future);

      container
          .read(ordersProvider.notifier)
          .cancelOrder('order-1', 'Fikrimi değiştirdim', '');

      final orders = container.read(ordersProvider).value!;
      final cancelled = orders.firstWhere((o) => o.id == 'order-1');
      final untouched = orders.firstWhere((o) => o.id == 'order-2');
      expect(cancelled.status, 'İptal Edildi');
      expect(untouched.status, isNot('İptal Edildi'));
    });

    test('submitReview updates only the matching order\'s review fields',
        () async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(() => _SignedInNotifier('uid-1'))
        ],
      );
      addTearDown(container.dispose);
      await container.read(canonicalOrderRepositoryProvider).submitOrder(
            _buildOrder(
              id: 'order-1',
              customerId: 'uid-1',
              status: OrderStatus.completed,
            ),
          );
      await container.read(ordersProvider.future);

      container.read(ordersProvider.notifier).submitReview(
            'order-1',
            const OrderModel(
              id: 'order-1',
              date: '',
              totalAmount: 0,
              status: '',
              overallRating: 5,
              reviewComment: 'Harika!',
            ),
          );

      final orders = container.read(ordersProvider).value!;
      final reviewed = orders.firstWhere((o) => o.id == 'order-1');
      expect(reviewed.overallRating, 5);
      expect(reviewed.reviewComment, 'Harika!');
    });
  });
}
