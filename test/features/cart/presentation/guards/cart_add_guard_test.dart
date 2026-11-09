import 'package:abakus_one_v2/features/cart/presentation/guards/cart_add_guard.dart';
import 'package:abakus_one_v2/features/menu/domain/models/menu_product.dart';
import 'package:abakus_one_v2/features/menu/domain/models/sale_unit.dart';
import 'package:abakus_one_v2/features/qr/presentation/providers/menu_showcase_mode_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _kgProduct = MenuProduct(
  id: 'prod_gramaj_test',
  categoryId: 'cat_gramajli',
  name: 'Gramajlı Test',
  description: '',
  basePrice: 1400,
  imageKey: 'does-not-exist',
  saleUnit: SaleUnit.kilogram,
);

const _pieceProduct = MenuProduct(
  id: 'prod_piece_test',
  categoryId: 'cat_test',
  name: 'Adetli Test',
  description: '',
  basePrice: 100,
  imageKey: 'does-not-exist',
);

void main() {
  late ProviderContainer container;
  late List<bool> results;

  setUp(() {
    container = ProviderContainer();
    results = [];
  });
  tearDown(() => container.dispose());

  Future<void> pumpAndTap(WidgetTester tester, MenuProduct? product) async {
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) => Scaffold(
            body: ElevatedButton(
              onPressed: () =>
                  results.add(allowCartAdd(context, ref, product: product)),
              child: const Text('Ekle'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Ekle'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'a kg product is refused in the customer app with the "ask staff" '
      'modal (the server would reject it without weightGrams)', (tester) async {
    await pumpAndTap(tester, _kgProduct);

    expect(results, [false]);
    expect(
        find.text(WeightProductOrderingBlockedDialog.message), findsOneWidget);
  });

  testWidgets('a per-piece product (or none) is allowed, no modal',
      (tester) async {
    await pumpAndTap(tester, _pieceProduct);
    expect(results, [true]);
    expect(find.byType(AlertDialog), findsNothing);

    await pumpAndTap(tester, null);
    expect(results, [true, true]);
  });

  testWidgets('showcase mode takes precedence: the table-QR modal wins',
      (tester) async {
    container.read(menuShowcaseModeProvider.notifier).enter();
    await pumpAndTap(tester, _kgProduct);

    expect(results, [false]);
    expect(find.text(ShowcaseOrderingBlockedDialog.message), findsOneWidget);
    expect(find.text(WeightProductOrderingBlockedDialog.message), findsNothing);
  });
}
