import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/features/cart/presentation/providers/cart_provider.dart';
import 'package:abakus_one_v2/features/reservation/presentation/providers/preorder_cart_provider.dart';
import 'package:abakus_one_v2/features/reservation/presentation/widgets/reservation_preorder_scope.dart';

/// Faz R.2 D4 — proves `ReservationPreorderScope` never touches the real
/// global `cartProvider`. Places one button outside the scope (writes to
/// the app's real cart, same as any existing menu/checkout screen would)
/// and one button inside it (writes wherever `cartProvider` resolves to
/// inside the nested scope — the isolated instance, if D4 is honored).
class _Harness extends StatelessWidget {
  const _Harness();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            Consumer(
              builder: (context, ref, _) => ElevatedButton(
                key: const Key('addOuter'),
                onPressed: () => ref.read(cartProvider.notifier).addToCart(
                      id: 'outer-item',
                      name: 'Outer Item',
                      desc: '',
                      price: 10,
                    ),
                child: const Text('Add Outer'),
              ),
            ),
            Expanded(
              child: ReservationPreorderScope(
                child: Consumer(
                  builder: (context, ref, _) => ElevatedButton(
                    key: const Key('addInner'),
                    onPressed: () => ref.read(cartProvider.notifier).addToCart(
                          id: 'preorder-item',
                          name: 'Preorder Item',
                          desc: '',
                          price: 20,
                        ),
                    child: const Text('Add Inner'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  testWidgets(
      'Faz R.2 D4 — adding an item inside ReservationPreorderScope never '
      'reaches the real global cartProvider, and vice versa', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: _Harness()));

    final outerContainer = ProviderScope.containerOf(
      tester.element(find.byType(_Harness)),
      listen: false,
    );

    // Seed the REAL global cart first, from outside the reservation flow —
    // exactly like any ordinary menu/checkout screen would.
    await tester.tap(find.byKey(const Key('addOuter')));
    await tester.pump();

    expect(outerContainer.read(cartProvider), hasLength(1));
    expect(outerContainer.read(cartProvider).single.id, 'outer-item');
    expect(outerContainer.read(preorderCartProvider), isEmpty);

    // Now add a different item from inside the nested preorder scope.
    await tester.tap(find.byKey(const Key('addInner')));
    await tester.pump();

    // The real cart must be completely unchanged — still only the
    // pre-existing outer item, never the preorder one.
    final realCart = outerContainer.read(cartProvider);
    expect(realCart, hasLength(1));
    expect(realCart.single.id, 'outer-item');

    // The preorder cart received the inner item instead.
    final preorderCart = outerContainer.read(preorderCartProvider);
    expect(preorderCart, hasLength(1));
    expect(preorderCart.single.id, 'preorder-item');
  });

  testWidgets(
      'adding to the real cart after the preorder scope has already written '
      'does not leak into the preorder cart either', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: _Harness()));

    final outerContainer = ProviderScope.containerOf(
      tester.element(find.byType(_Harness)),
      listen: false,
    );

    await tester.tap(find.byKey(const Key('addInner')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('addOuter')));
    await tester.pump();

    final preorderCart = outerContainer.read(preorderCartProvider);
    expect(preorderCart, hasLength(1));
    expect(preorderCart.single.id, 'preorder-item');

    final realCart = outerContainer.read(cartProvider);
    expect(realCart, hasLength(1));
    expect(realCart.single.id, 'outer-item');
  });
}
