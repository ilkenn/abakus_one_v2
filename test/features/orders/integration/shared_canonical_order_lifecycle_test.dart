import 'package:abakus_one_v2/features/cart/domain/models/cart_item.dart';
import 'package:abakus_one_v2/features/orders/application/use_cases/submit_customer_order.dart';
import 'package:abakus_one_v2/features/orders/data/canonical_order_repository.dart';
import 'package:abakus_one_v2/features/orders/domain/identity/order_identity.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_model.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_status.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/submit_pos_order.dart';
import 'package:abakus_one_v2/features/pos/data/pos_order_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../pos/test_support/fake_clock.dart';
import '../../pos/test_support/pos_test_fixtures.dart';

/// Proves Sprint 9D's central architectural claim (`docs/decisions.md`
/// ADR-026): a POS-submitted order and a customer-checkout-submitted
/// order are genuinely the same kind of object, going through the same
/// lifecycle, landing in the same store — not two independently-evolving
/// models that merely look similar.
void main() {
  test(
      'an order submitted via SubmitPosOrder and one via SubmitCustomerOrder '
      'land in the same CanonicalOrderRepository when wired to the same '
      'instance — mirroring how canonicalOrderRepositoryProvider wires '
      'both in the running app', () async {
    final sharedRepository = InMemoryCanonicalOrderRepository();
    final posRepository =
        InMemoryPosOrderRepository(canonicalOrderRepository: sharedRepository);
    final identityProvider = InMemoryOrderIdentityProvider();
    final clock = FakeClock(DateTime(2026, 8, 5, 18, 0));

    final posSession =
        buildTestSession(sessionId: 'session-1', openedAt: clock.now())
            .copyWith(lines: [
      buildTestLineDraft(
        item: const CartItem(
            id: 'p1', name: 'Bowl', desc: '', price: 100.0, quantity: 1),
      ),
    ]);
    final posOrder = await SubmitPosOrder(
      clock: clock,
      identityProvider: identityProvider,
      repository: posRepository,
      restaurantId: 'restaurant-1',
    ).call(posSession);

    final customerOrder = await SubmitCustomerOrder(
      clock: clock,
      identityProvider: identityProvider,
      repository: sharedRepository,
      branchId: 'branch-1',
      restaurantId: 'restaurant-1',
    ).call(
      cartItems: const [
        CartItem(id: 'p2', name: 'Salad', desc: '', price: 80.0, quantity: 1),
      ],
      customerId: 'uid-1',
    );

    final all = await sharedRepository.findAll();
    expect(all, containsAll([posOrder, customerOrder]));

    // Both entered the same lifecycle: same status, same transition rule,
    // same aggregate type.
    expect(posOrder.status, OrderStatus.pendingConfirmation);
    expect(customerOrder.status, OrderStatus.pendingConfirmation);

    // Channel-appropriate defaults are preserved per order, not collapsed
    // into one another.
    expect(posOrder.channel, isNot(OrderChannel.delivery));
    expect(customerOrder.channel, OrderChannel.delivery);
    expect(posOrder.customerId, isNull);
    expect(customerOrder.customerId, 'uid-1');

    // Both are retrievable through PosOrderRepository.findById too, since
    // it now delegates to the same shared store.
    expect(await posRepository.findById(customerOrder.id), customerOrder);
  });

  test(
      'OrderModel.fromCanonicalOrder projects a real canonical Order into '
      'the shape the legacy customer-facing order screens read, with the '
      'correct legacy status label', () async {
    final order = await SubmitCustomerOrder(
      clock: FakeClock(DateTime(2026, 8, 5, 18, 0)),
      identityProvider: InMemoryOrderIdentityProvider(),
      repository: InMemoryCanonicalOrderRepository(),
      branchId: 'branch-1',
      restaurantId: 'restaurant-1',
    ).call(
      cartItems: const [
        CartItem(id: 'p1', name: 'Bowl', desc: '', price: 100.0, quantity: 2),
      ],
      customerId: 'uid-1',
      customerNote: 'Zil çalınsın',
    );

    final projected = OrderModel.fromCanonicalOrder(order);

    expect(projected.id, order.id.value);
    expect(projected.status, 'Onay Bekliyor');
    expect(projected.lifecycleStatus, OrderStatus.pendingConfirmation);
    expect(projected.channel, OrderChannel.delivery);
    expect(projected.items, hasLength(1));
    expect(projected.items.single.quantity, 2);
    expect(projected.orderNote, 'Zil çalınsın');
  });
}
