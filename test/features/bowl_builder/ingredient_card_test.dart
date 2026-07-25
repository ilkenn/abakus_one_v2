import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/bowl_builder/presentation/widgets/ingredient_card.dart';

void main() {
  Future<void> pumpCard(WidgetTester tester, Widget card) {
    return tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: SizedBox(width: 200, child: card)),
        ),
      ),
    );
  }

  group('toggle modu (allowsQuantity: false)', () {
    testWidgets('karta dokununca onTap tetiklenir', (tester) async {
      var tapped = false;
      await pumpCard(
        tester,
        IngredientCard(
          name: 'Mevsim Salata',
          price: 15,
          imageKey: 'salad_mevsim',
          quantity: 0,
          allowsQuantity: false,
          onTap: () => tapped = true,
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Mevsim Salata'));
      await tester.pump();

      expect(tapped, isTrue);
    });

    testWidgets('quantity 0 iken check rozeti gizli, gorunmez opaklikta', (
      tester,
    ) async {
      await pumpCard(
        tester,
        IngredientCard(
          name: 'Roka',
          price: 15,
          imageKey: 'salad_roka',
          quantity: 0,
          allowsQuantity: false,
          onTap: () {},
        ),
      );
      await tester.pump();

      final opacity = tester.widget<AnimatedOpacity>(
        find.byType(AnimatedOpacity),
      );
      expect(opacity.opacity, 0.0);
    });

    testWidgets('quantity 1 iken check rozeti gorunur opaklikta', (
      tester,
    ) async {
      await pumpCard(
        tester,
        IngredientCard(
          name: 'Roka',
          price: 15,
          imageKey: 'salad_roka',
          quantity: 1,
          allowsQuantity: false,
          onTap: () {},
        ),
      );
      await tester.pumpAndSettle();

      final opacity = tester.widget<AnimatedOpacity>(
        find.byType(AnimatedOpacity),
      );
      expect(opacity.opacity, 1.0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Semantics secili durumu ve fiyati dogru anlatir', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();

      await pumpCard(
        tester,
        IngredientCard(
          name: 'Roka',
          price: 15,
          imageKey: 'salad_roka',
          quantity: 1,
          allowsQuantity: false,
          onTap: () {},
        ),
      );
      await tester.pump();

      expect(find.bySemanticsLabel('Roka, +15 TL, seçili'), findsOneWidget);
      handle.dispose();
    });
  });

  group('miktar modu (allowsQuantity: true)', () {
    testWidgets('+ butonu onIncrement tetikler', (tester) async {
      var incremented = false;
      await pumpCard(
        tester,
        IngredientCard(
          name: 'Izgara Tavuk',
          price: 40,
          imageKey: 'protein_izgara_tavuk',
          quantity: 0,
          allowsQuantity: true,
          onIncrement: () => incremented = true,
          onDecrement: () {},
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump();

      expect(incremented, isTrue);
    });

    testWidgets('quantity 0 iken - butonu devre disidir', (tester) async {
      await pumpCard(
        tester,
        IngredientCard(
          name: 'Izgara Tavuk',
          price: 40,
          imageKey: 'protein_izgara_tavuk',
          quantity: 0,
          allowsQuantity: true,
          onIncrement: () {},
          onDecrement: () {},
        ),
      );
      await tester.pump();

      final minusButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.remove_rounded),
      );
      expect(minusButton.onPressed, isNull);
    });

    testWidgets('quantity artinca pulse animasyonu exception firlatmaz', (
      tester,
    ) async {
      final key = GlobalKey();
      var quantity = 0;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                key: key,
                builder: (context, setState) {
                  return SizedBox(
                    width: 200,
                    child: IngredientCard(
                      name: 'Izgara Tavuk',
                      price: 40,
                      imageKey: 'protein_izgara_tavuk',
                      quantity: quantity,
                      allowsQuantity: true,
                      onIncrement: () => setState(() => quantity++),
                      onDecrement: () => setState(() => quantity--),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Semantics secili adedi dogru anlatir', (tester) async {
      final handle = tester.ensureSemantics();

      await pumpCard(
        tester,
        IngredientCard(
          name: 'Izgara Tavuk',
          price: 40,
          imageKey: 'protein_izgara_tavuk',
          quantity: 3,
          allowsQuantity: true,
          onIncrement: () {},
          onDecrement: () {},
        ),
      );
      await tester.pump();

      expect(
        find.bySemanticsLabel('Izgara Tavuk, +40 TL, 3 adet seçili'),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  testWidgets('gercek foto olmadigi icin placeholder ikon gosterir', (
    tester,
  ) async {
    await pumpCard(
      tester,
      IngredientCard(
        name: 'Roka',
        price: 15,
        imageKey: 'salad_roka',
        quantity: 0,
        allowsQuantity: false,
        onTap: () {},
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.fastfood_rounded), findsOneWidget);
  });
}
