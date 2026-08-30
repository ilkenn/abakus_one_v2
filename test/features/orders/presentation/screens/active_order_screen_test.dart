import 'package:abakus_one_v2/features/orders/application/use_cases/submit_customer_order.dart';
import 'package:abakus_one_v2/features/orders/data/canonical_order_repository.dart';
import 'package:abakus_one_v2/features/orders/domain/identity/order_identity.dart';
import 'package:abakus_one_v2/features/orders/domain/models/dine_in_counter_proposal.dart';
import 'package:abakus_one_v2/features/orders/domain/models/dine_in_line_status.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_line_approval_state.dart';
import 'package:abakus_one_v2/features/orders/presentation/providers/dine_in_counter_proposal_dependencies_provider.dart';
import 'package:abakus_one_v2/features/orders/presentation/providers/orders_provider.dart';
import 'package:abakus_one_v2/features/orders/presentation/screens/active_order_screen.dart';
import 'package:abakus_one_v2/features/cart/domain/models/cart_item.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:abakus_one_v2/shared/widgets/feedback/empty_view.dart';
import 'package:abakus_one_v2/shared/widgets/feedback/error_view.dart';
import 'package:abakus_one_v2/shared/widgets/feedback/loading_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../pos/test_support/fake_clock.dart';

/// A [CanonicalOrderRepository] whose [findById] can be made to throw on
/// demand — [InMemoryCanonicalOrderRepository] alone has no error path,
/// and `ActiveOrderScreen`'s error/retry state needs one to exercise.
class _ThrowingOnceRepository implements CanonicalOrderRepository {
  _ThrowingOnceRepository(this._delegate);

  final InMemoryCanonicalOrderRepository _delegate;
  bool shouldThrow = false;

  @override
  Future<Order> submitOrder(Order order) => _delegate.submitOrder(order);

  @override
  Future<List<Order>> findAll() => _delegate.findAll();

  @override
  Future<List<Order>> findByCustomerId(String customerId) =>
      _delegate.findByCustomerId(customerId);

  @override
  Future<Order?> findById(OrderId orderId) async {
    if (shouldThrow) throw Exception('simulated repository failure');
    return _delegate.findById(orderId);
  }
}

Future<Order> _buildDineInOrder({
  required InMemoryCanonicalOrderRepository repository,
  String productId = 'p1',
  String productName = 'Klasik Bowl',
  double price = 100,
}) async {
  return SubmitCustomerOrder(
    clock: FakeClock(DateTime(2026, 8, 5, 18, 30)),
    identityProvider: InMemoryOrderIdentityProvider(),
    repository: repository,
    branchId: 'branch-1',
    restaurantId: 'restaurant-1',
  ).call(
    cartItems: [
      CartItem(
        id: productId,
        name: productName,
        desc: '',
        price: price,
        quantity: 1,
      ),
    ],
    customerId: 'uid-1',
    channel: OrderChannel.dineInQr,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required CanonicalOrderRepository repository,
  String? orderId,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        canonicalOrderRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        home: ActiveOrderScreen(orderId: orderId),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'orderId provided: shows the canonical order\'s product and total, '
    'read via the guest-safe canonical-by-id path (never ordersProvider)',
    (tester) async {
      final repository = InMemoryCanonicalOrderRepository();
      final order = await _buildDineInOrder(repository: repository);
      await repository.submitOrder(order);

      await _pump(tester, repository: repository, orderId: order.id.value);

      expect(find.text('Klasik Bowl'), findsOneWidget);
      expect(find.text('Sipariş İçeriği'), findsOneWidget);
      expect(find.text('Ödeme Özeti'), findsOneWidget);
    },
  );

  testWidgets(
    'AP-3 wave 7 correction: after a counter-proposal is accepted, the '
    'canonical replacement product and the recomputed total are shown — '
    'never the original product/total, and never requiring a restart',
    (tester) async {
      final repository = InMemoryCanonicalOrderRepository();
      // The order AS IT EXISTS after a real backend accept: the line's
      // productId/productName/unitPrice already point at the replacement
      // (exactly what `respondToDineInCounterProposal`'s accept branch
      // writes in place — see order_firestore_mapper.dart's _lineFromFirestore,
      // which derives OrderLine from the SAME raw map lineApprovalStates
      // reads its status from), and pricing.grandTotal already reflects the
      // AP-3 wave 7 backend recompute fix (dineInCounterProposal.ts's
      // recomputeOrderPricing).
      final accepted = await _buildDineInOrder(
        repository: repository,
        productId: 'p2',
        productName: 'Yeşil Salata',
        price: 95,
      );
      final withAcceptedProposal = accepted.copyWith(lineApprovalStates: [
        OrderLineApprovalState(
          lineIndex: 0,
          status: DineInLineStatus.accepted,
          counterProposal: DineInCounterProposal(
            proposalVersion: 1,
            proposedProductId: 'p2',
            proposedProductName: 'Yeşil Salata',
            proposedModifiers: const [],
            proposedQuantity: 1,
            proposedUnitPrice: Money.fromWhole(95, Currency.tryLira),
            proposedLineTotal: Money.fromWhole(95, Currency.tryLira),
            differenceFromOriginal: Money.fromWhole(-335, Currency.tryLira),
            reasonCode: 'outOfStock',
            reasonMessage: 'Mexifit Bowl için tavuk stoğumuz tükendi.',
            proposedByStaffUid: 'staff-uid-1',
            createdAt: DateTime(2026, 8, 5, 18, 25),
            expiresAt: DateTime(2026, 8, 5, 18, 40),
            status: DineInCounterProposalStatus.accepted,
            respondedAt: DateTime(2026, 8, 5, 18, 27),
          ),
        ),
      ]);
      await repository.submitOrder(withAcceptedProposal);

      await _pump(tester, repository: repository, orderId: accepted.id.value);

      // The replacement is shown as the order's actual content — never the
      // pre-proposal "Mexifit Bowl" original.
      expect(find.text('Yeşil Salata'), findsOneWidget);
      expect(find.text('Mexifit Bowl'), findsNothing);
      // Totals reflect the replacement's price (95 TL), never the original.
      expect(find.textContaining('95 TL'), findsWidgets);
      expect(find.textContaining('430 TL'), findsNothing);
      // Resolved — the approval-workflow section has nothing left to show.
      expect(find.text('Değişiklik Önerisi'), findsNothing);
      expect(find.text('Onay bekliyor'), findsNothing);
    },
  );

  testWidgets(
    'orderId provided: a rejected counter-proposal leaves the ORIGINAL '
    'product and total shown, never the rejected replacement',
    (tester) async {
      final repository = InMemoryCanonicalOrderRepository();
      final original = await _buildDineInOrder(
        repository: repository,
        productId: 'p1',
        productName: 'Mexifit Bowl',
        price: 430,
      );
      final withRejectedProposal = original.copyWith(lineApprovalStates: [
        OrderLineApprovalState(
          lineIndex: 0,
          status: DineInLineStatus.rejected,
          counterProposal: DineInCounterProposal(
            proposalVersion: 1,
            proposedProductId: 'p2',
            proposedProductName: 'Yeşil Salata',
            proposedModifiers: const [],
            proposedQuantity: 1,
            proposedUnitPrice: Money.fromWhole(95, Currency.tryLira),
            proposedLineTotal: Money.fromWhole(95, Currency.tryLira),
            differenceFromOriginal: Money.fromWhole(-335, Currency.tryLira),
            reasonCode: 'outOfStock',
            reasonMessage: 'Mexifit Bowl için tavuk stoğumuz tükendi.',
            proposedByStaffUid: 'staff-uid-1',
            createdAt: DateTime(2026, 8, 5, 18, 25),
            expiresAt: DateTime(2026, 8, 5, 18, 40),
            status: DineInCounterProposalStatus.rejected,
            respondedAt: DateTime(2026, 8, 5, 18, 27),
          ),
        ),
      ]);
      await repository.submitOrder(withRejectedProposal);

      await _pump(tester, repository: repository, orderId: original.id.value);

      // findsWidgets, not findsOneWidget: DineInLineApprovalSection also
      // shows a "Mexifit Bowl · Reddedildi" status row for a rejected line
      // (correct, matches real behavior) alongside _OrderItemsCard's own
      // product row — this test only asserts the original product appears
      // and the rejected replacement never does, not an exact widget count.
      expect(find.text('Mexifit Bowl'), findsWidgets);
      expect(find.text('Yeşil Salata'), findsNothing);
      expect(find.textContaining('430 TL'), findsWidgets);
    },
  );

  testWidgets(
    'orderId provided: the screen updates live when the canonical provider '
    'is invalidated, without navigating away and back',
    (tester) async {
      final repository = InMemoryCanonicalOrderRepository();
      final order = await _buildDineInOrder(
        repository: repository,
        productId: 'p1',
        productName: 'Mexifit Bowl',
        price: 430,
      );
      await repository.submitOrder(order);

      final container = ProviderContainer(overrides: [
        canonicalOrderRepositoryProvider.overrideWithValue(repository),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: ActiveOrderScreen(orderId: order.id.value),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Mexifit Bowl'), findsOneWidget);

      // Simulate the real backend accept: the SAME order id is resubmitted
      // with the replacement product/price, then the provider is
      // invalidated exactly the way DineInLineApprovalSection's own
      // accept/reject handler already does after a real gateway call —
      // proving ActiveOrderScreen rebuilds through that same signal with no
      // extra wiring of its own.
      final replaced = order.copyWith(
        lines: [
          (await _buildDineInOrder(
            repository: InMemoryCanonicalOrderRepository(),
            productId: 'p2',
            productName: 'Yeşil Salata',
            price: 95,
          ))
              .lines
              .single,
        ],
      );
      await repository.submitOrder(replaced);
      container.invalidate(canonicalOrderByIdProvider(order.id.value));
      await tester.pumpAndSettle();

      expect(find.text('Yeşil Salata'), findsOneWidget);
      expect(find.text('Mexifit Bowl'), findsNothing);
    },
  );

  testWidgets(
    'orderId provided: an order that does not exist (or is not authorized '
    'for this actor) shows the empty state, never a crash',
    (tester) async {
      final repository = InMemoryCanonicalOrderRepository();

      await _pump(tester, repository: repository, orderId: 'no-such-order');

      expect(find.byType(EmptyView), findsOneWidget);
      expect(
        find.text('Şu anda takip edebileceğiniz aktif bir siparişiniz yok.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'orderId provided: a repository failure shows a bounded, retryable '
    'error state, never hangs or crashes',
    (tester) async {
      final repository = _ThrowingOnceRepository(
        InMemoryCanonicalOrderRepository(),
      )..shouldThrow = true;

      await _pump(tester, repository: repository, orderId: 'order-x');

      expect(find.byType(ErrorView), findsOneWidget);
      expect(find.text('Tekrar Dene'), findsOneWidget);

      repository.shouldThrow = false;
      await tester.tap(find.text('Tekrar Dene'));
      await tester.pumpAndSettle();

      expect(find.byType(EmptyView), findsOneWidget);
    },
  );

  testWidgets(
    'orderId omitted: falls back to the current-active-order path '
    '(unchanged pre-existing behavior)',
    (tester) async {
      final repository = InMemoryCanonicalOrderRepository();

      await _pump(tester, repository: repository, orderId: null);

      expect(find.byType(LoadingView), findsNothing);
      expect(find.byType(EmptyView), findsOneWidget);
      expect(
        find.text('Şu anda takip edebileceğiniz aktif bir siparişiniz yok.'),
        findsOneWidget,
      );
    },
  );
}
