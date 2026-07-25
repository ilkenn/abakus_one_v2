import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/bowl_builder/presentation/providers/bowl_builder_provider.dart';
import 'package:abakus_one_v2/features/bowl_builder/presentation/screens/bowl_builder_screen.dart';
import 'package:abakus_one_v2/features/bowl_builder/presentation/widgets/bowl_canvas.dart';
import 'package:abakus_one_v2/features/bowl_builder/presentation/widgets/ingredient_card.dart';
import 'package:abakus_one_v2/features/cart/presentation/providers/cart_provider.dart';

void main() {
  /// Phone-sized by default so the ingredient grid is deterministically
  /// single-column (see `AppBreakpoints`) — the responsive-column behavior
  /// itself is covered separately, below.
  Future<void> pumpBowlBuilder(
    WidgetTester tester, {
    Size viewportSize = const Size(400, 900),
  }) async {
    tester.view.physicalSize = viewportSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: BowlBuilderScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapDevamEt(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(ElevatedButton, 'Devam Et'));
    await tester.pumpAndSettle();
  }

  Future<void> advanceSteps(WidgetTester tester, int count) async {
    for (var i = 0; i < count; i++) {
      await tapDevamEt(tester);
    }
  }

  /// Toggles a non-quantity-category ingredient by tapping its card.
  ///
  /// Uses `scrollUntilVisible` rather than `ensureVisible` — the grid is a
  /// lazy `SliverGrid`, so an ingredient further down the list may not be
  /// built into the tree at all yet, and `ensureVisible` only scrolls
  /// widgets that already exist.
  Future<void> tapToggleIngredient(WidgetTester tester, String name) async {
    final finder = find.text(name);
    await tester.scrollUntilVisible(finder, 200);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// Taps the +/- stepper button inside the [IngredientCard] for [name]
  /// (Proteinler/Karbonhidratlar only).
  Future<void> tapIngredientStepper(
    WidgetTester tester,
    String name, {
    required bool increment,
  }) async {
    final card = find.ancestor(
      of: find.text(name),
      matching: find.byType(IngredientCard),
    );
    await tester.scrollUntilVisible(card, 200);
    await tester.pumpAndSettle();
    final icon = find.descendant(
      of: card,
      matching:
          find.byIcon(increment ? Icons.add_rounded : Icons.remove_rounded),
    );
    await tester.tap(icon);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Bowl Builder acilir, hicbir baslangic fiyati iddia etmez, toplam 0 TL ile baslar',
    (tester) async {
      await pumpBowlBuilder(tester);

      expect(find.byType(BowlBuilderScreen), findsOneWidget);
      expect(find.textContaining('TL\'den başlayan'), findsNothing);
      expect(find.text('0 TL'), findsOneWidget);
      expect(find.text('Proteinler'), findsOneWidget);
    },
  );

  testWidgets(
    'Proteinler: stepper ile arttirinca fiyat price x adet olarak artar',
    (tester) async {
      await pumpBowlBuilder(tester);

      await tapIngredientStepper(tester, 'Izgara Tavuk', increment: true);
      expect(find.text('40 TL'), findsOneWidget);

      await tapIngredientStepper(tester, 'Izgara Tavuk', increment: true);
      expect(find.text('80 TL'), findsOneWidget);

      await tapIngredientStepper(tester, 'Izgara Tavuk', increment: false);
      expect(find.text('40 TL'), findsOneWidget);
    },
  );

  testWidgets(
    'Proteinler: farkli iki urun ayni anda, sinirsiz sekilde secilebilir',
    (tester) async {
      await pumpBowlBuilder(tester);

      await tapIngredientStepper(tester, 'Izgara Tavuk', increment: true);
      await tapIngredientStepper(tester, 'Dana Bonfile', increment: true);

      final container = ProviderScope.containerOf(
          tester.element(find.byType(BowlBuilderScreen)));
      final state = container.read(bowlBuilderProvider);
      expect(state.quantityFor('bb_protein_izgara_tavuk'), 1);
      expect(state.quantityFor('bb_protein_dana_bonfile'), 1);
      // 40 (Izgara Tavuk) + 150 (Dana Bonfile).
      expect(find.text('190 TL'), findsOneWidget);
    },
  );

  testWidgets(
    'stepper - butonu 0 iken devre disidir, negatife dusmez',
    (tester) async {
      await pumpBowlBuilder(tester);

      final card = find.ancestor(
        of: find.text('Izgara Tavuk'),
        matching: find.byType(IngredientCard),
      );
      final minusButton = find.descendant(
        of: card,
        matching: find.widgetWithIcon(IconButton, Icons.remove_rounded),
      );
      final button = tester.widget<IconButton>(minusButton);
      expect(button.onPressed, isNull);
    },
  );

  testWidgets(
    'Salatalar: bir porsiyon secilir, tekrar tiklaninca kaldirilir',
    (tester) async {
      await pumpBowlBuilder(tester);
      await advanceSteps(tester, 2); // Proteinler, Karbonhidratlar -> Salatalar
      expect(find.text('Salatalar'), findsOneWidget);

      await tapToggleIngredient(tester, 'Mevsim Salata');
      expect(find.text('15 TL'), findsOneWidget);

      await tapToggleIngredient(tester, 'Mevsim Salata');
      expect(find.text('0 TL'), findsOneWidget);
    },
  );

  testWidgets(
    'Salatalar: yapay ust sinir yok, birden fazla farkli malzeme secilebilir',
    (tester) async {
      await pumpBowlBuilder(tester);
      await advanceSteps(tester, 2);
      expect(find.text('Salatalar'), findsOneWidget);

      await tapToggleIngredient(tester, 'Mevsim Salata'); // 15
      await tapToggleIngredient(tester, 'Kıvırcık Marul'); // 15
      await tapToggleIngredient(tester, 'Roka'); // 15
      await tapToggleIngredient(tester, 'Baby Ispanak'); // 30

      final container = ProviderScope.containerOf(
          tester.element(find.byType(BowlBuilderScreen)));
      final state = container.read(bowlBuilderProvider);
      expect(state.quantityFor('bb_salad_mevsim'), 1);
      expect(state.quantityFor('bb_salad_kivircik_marul'), 1);
      expect(state.quantityFor('bb_salad_roka'), 1);
      expect(state.quantityFor('bb_salad_baby_ispanak'), 1);
      expect(find.text('75 TL'), findsOneWidget); // 15+15+15+30
    },
  );

  testWidgets('geri gidildiginde onceki adimlardaki secimler korunur', (
    tester,
  ) async {
    await pumpBowlBuilder(tester);

    await tapIngredientStepper(tester, 'Izgara Tavuk', increment: true);
    await tapDevamEt(tester); // -> Karbonhidratlar
    await tapDevamEt(tester); // -> Salatalar
    expect(find.text('Salatalar'), findsOneWidget);
    await tapToggleIngredient(tester, 'Roka');

    await tester.tap(find.widgetWithText(OutlinedButton, 'Geri'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Geri'));
    await tester.pumpAndSettle();
    expect(find.text('Proteinler'), findsOneWidget);

    final container = ProviderScope.containerOf(
        tester.element(find.byType(BowlBuilderScreen)));
    expect(
      container
          .read(bowlBuilderProvider)
          .quantityFor('bb_protein_izgara_tavuk'),
      1,
    );

    await tapDevamEt(tester);
    await tapDevamEt(tester);
    expect(
      container.read(bowlBuilderProvider).quantityFor('bb_salad_roka'),
      1,
    );
  });

  testWidgets('bowl adedi artirilinca toplam fiyat dogru carpanla guncellenir',
      (
    tester,
  ) async {
    await pumpBowlBuilder(tester);

    await tapIngredientStepper(tester, 'Izgara Tavuk', increment: true); // 40
    await advanceSteps(tester, 9); // Karbonhidratlar ... Soslar -> Özet

    expect(find.text('Bowl Özeti'), findsOneWidget);

    await tester.ensureVisible(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add_rounded)); // bowl adedi 2
    await tester.pumpAndSettle();

    expect(find.text('80 TL'), findsWidgets); // 40 * 2
    expect(
      find.widgetWithText(ElevatedButton, 'Sepete Ekle · 80 TL'),
      findsOneWidget,
    );
  });

  testWidgets(
    'ozet ekrani ayni malzemeden birden fazlasini "x N" ile gosterir',
    (tester) async {
      await pumpBowlBuilder(tester);

      await tapIngredientStepper(tester, 'Izgara Tavuk', increment: true);
      await tapIngredientStepper(tester, 'Izgara Tavuk', increment: true);
      await tapIngredientStepper(tester, 'Izgara Tavuk', increment: true);
      await advanceSteps(tester, 9);

      expect(find.text('Bowl Özeti'), findsOneWidget);
      expect(find.text('Izgara Tavuk × 3'), findsOneWidget);
    },
  );

  testWidgets(
    'not ve secimler sepete dogru fiyatla aktarilir',
    (tester) async {
      await pumpBowlBuilder(tester);

      await tapIngredientStepper(tester, 'Izgara Tavuk', increment: true); // 40
      await tapDevamEt(tester); // -> Karbonhidratlar
      await tapDevamEt(tester); // -> Salatalar
      await tapToggleIngredient(tester, 'Roka'); // 15
      await advanceSteps(tester, 7); // Sebzeler ... Soslar -> Özet

      expect(find.text('Bowl Özeti'), findsOneWidget);

      await tester.ensureVisible(find.byType(TextField));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Sos az olsun');
      await tester.pumpAndSettle();

      // 40 (Izgara Tavuk) + 15 (Roka) = 55 TL.
      expect(find.text('55 TL'), findsWidgets);

      final context = tester.element(find.byType(BowlBuilderScreen));
      final container = ProviderScope.containerOf(context);

      await tester.ensureVisible(
        find.widgetWithText(ElevatedButton, 'Sepete Ekle · 55 TL'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(ElevatedButton, 'Sepete Ekle · 55 TL'),
      );
      await tester.pumpAndSettle();

      final cartItems = container.read(cartProvider);
      expect(cartItems, hasLength(1));
      final item = cartItems.first;
      expect(item.name, 'Kendi Bowlun');
      expect(item.note, 'Sos az olsun');
      expect(item.quantity, 1);
      expect(item.price, 0);
      expect(
        item.selectedModifiers.map((m) => m.optionName).toSet(),
        {'Izgara Tavuk', 'Roka'},
      );
      expect(item.totalRowPrice, 55);
    },
  );

  testWidgets(
    'hicbir secim yapilmadan urun 0 TL ile sepete eklenebilir',
    (tester) async {
      await pumpBowlBuilder(tester);

      await advanceSteps(tester, 9); // dogrudan Özet'e

      expect(find.text('Bowl Özeti'), findsOneWidget);
      expect(
        find.widgetWithText(ElevatedButton, 'Sepete Ekle · 0 TL'),
        findsOneWidget,
      );

      final context = tester.element(find.byType(BowlBuilderScreen));
      final container = ProviderScope.containerOf(context);

      await tester.tap(
        find.widgetWithText(ElevatedButton, 'Sepete Ekle · 0 TL'),
      );
      await tester.pumpAndSettle();

      final cartItems = container.read(cartProvider);
      expect(cartItems, hasLength(1));
      expect(cartItems.first.selectedModifiers, isEmpty);
      expect(cartItems.first.totalRowPrice, 0);
    },
  );

  group('canli bowl onizlemesi (Faz 8.3)', () {
    testWidgets(
      'secim adimlarinda tam olarak bir BowlCanvas gorunur (kompakt onizleme)',
      (tester) async {
        await pumpBowlBuilder(tester);

        expect(find.text('Proteinler'), findsOneWidget);
        expect(find.byType(BowlCanvas), findsOneWidget);
      },
    );

    testWidgets(
      'ozet adiminda da tam olarak bir BowlCanvas gorunur, iki tane degil',
      (tester) async {
        await pumpBowlBuilder(tester);
        await advanceSteps(tester, 9);

        expect(find.text('Bowl Özeti'), findsOneWidget);
        expect(find.byType(BowlCanvas), findsOneWidget);
      },
    );

    testWidgets(
      'malzeme secilince onizleme, sayfa yeniden olusturulmadan aninda guncellenir',
      (tester) async {
        await pumpBowlBuilder(tester);

        expect(
          find.descendant(
            of: find.byType(BowlCanvas),
            matching: find.byWidgetPredicate(
              (w) =>
                  w is Image &&
                  w.image is AssetImage &&
                  (w.image as AssetImage).assetName ==
                      'assets/images/bowl/layers/izgara_tavuk.png',
            ),
          ),
          findsNothing, // henuz hicbir sey secilmedi
        );

        await tapIngredientStepper(tester, 'Izgara Tavuk', increment: true);

        expect(
          find.descendant(
            of: find.byType(BowlCanvas),
            matching: find.byWidgetPredicate(
              (w) =>
                  w is Image &&
                  w.image is AssetImage &&
                  (w.image as AssetImage).assetName ==
                      'assets/images/bowl/layers/izgara_tavuk.png',
            ),
          ),
          findsOneWidget,
        );
        // Ayni BowlBuilderScreen ornegi hala ekranda - sayfa yenilenmedi.
        expect(find.byType(BowlBuilderScreen), findsOneWidget);
      },
    );

    testWidgets(
      'adimlar arasinda gecince onizleme state korunur, animasyon tekrar baslamaz',
      (tester) async {
        await pumpBowlBuilder(tester);

        await tapIngredientStepper(tester, 'Izgara Tavuk', increment: true);
        await tester.pumpAndSettle();

        final fadeBefore = tester.widget<FadeTransition>(
          find.descendant(
            of: find.byType(BowlCanvas),
            matching: find.byType(FadeTransition),
          ),
        );
        expect(fadeBefore.opacity.value, 1.0);

        await tapDevamEt(tester); // -> Karbonhidratlar
        await tester.pump(); // step-transition animasyonunun ilk frame'i

        // Karbonhidratlar adiminda da hala ayni secim goruntuleniyor,
        // animasyonu bastan baslamadan (zaten tam opaklikta).
        final fadeAfter = tester.widget<FadeTransition>(
          find.descendant(
            of: find.byType(BowlCanvas),
            matching: find.byType(FadeTransition),
          ),
        );
        expect(fadeAfter.opacity.value, 1.0);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('responsive grid', () {
    Future<int> pumpAndGetColumnCount(
      WidgetTester tester,
      Size viewportSize,
    ) async {
      await pumpBowlBuilder(tester, viewportSize: viewportSize);
      final delegate = tester
          .widget<SliverGrid>(find.byType(SliverGrid))
          .gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      return delegate.crossAxisCount;
    }

    testWidgets('telefon genisliginde tek sutun', (tester) async {
      final columns = await pumpAndGetColumnCount(
        tester,
        const Size(400, 900),
      );
      expect(columns, 1);
    });

    testWidgets('tablet genisliginde iki sutun', (tester) async {
      final columns = await pumpAndGetColumnCount(
        tester,
        const Size(700, 900),
      );
      expect(columns, 2);
    });

    testWidgets('buyuk tablet/web genisliginde uc sutun', (tester) async {
      final columns = await pumpAndGetColumnCount(
        tester,
        const Size(1000, 900),
      );
      expect(columns, 3);
    });
  });
}
