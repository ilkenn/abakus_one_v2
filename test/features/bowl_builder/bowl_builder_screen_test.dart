import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/bowl_builder/presentation/providers/bowl_builder_provider.dart';
import 'package:abakus_one_v2/features/bowl_builder/presentation/screens/bowl_builder_screen.dart';
import 'package:abakus_one_v2/features/bowl_builder/presentation/widgets/bowl_canvas.dart';
import 'package:abakus_one_v2/features/bowl_builder/presentation/widgets/build_your_bowl_hero.dart';
import 'package:abakus_one_v2/features/bowl_builder/presentation/widgets/builder_progress.dart';
import 'package:abakus_one_v2/features/bowl_builder/presentation/widgets/ingredient_card.dart';
import 'package:abakus_one_v2/features/cart/presentation/providers/cart_provider.dart';

void main() {
  /// Phone-sized by default.
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

  final categorySelector = find.byKey(const Key('categorySelectorListView'));
  final ingredientCarousel =
      find.byKey(const Key('ingredientCarouselListView'));

  /// Jumps directly to any category, from anywhere — the whole point of
  /// the v2 redesign is that no linear progression is required. Scrolls
  /// the category selector (its own, always-on-screen horizontal list)
  /// left until [label] is found, then taps it.
  Future<void> tapCategory(WidgetTester tester, String label) async {
    // Always start from the beginning of the row — a previous jump may
    // have left it scrolled past where `label` now sits, and a fixed
    // "-150" drag can only ever reveal *later* chips, never scroll back.
    await tester.drag(categorySelector, const Offset(2000, 0));
    await tester.pumpAndSettle();

    final target = find.text(label);
    var attempts = 0;
    while (target.evaluate().isEmpty && attempts < 12) {
      await tester.drag(categorySelector, const Offset(-150, 0));
      await tester.pumpAndSettle();
      attempts++;
    }
    // Being mounted (found in the tree) isn't the same as being fully
    // on-screen — a lazily-built horizontal list can mount an item that's
    // only partially visible at the trailing edge of the viewport, whose
    // geometric center then falls outside the hit-testable area.
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  /// Scrolls the *active category's* ingredient carousel (a lazily-built
  /// horizontal `ListView`) until [name] is mounted, then walks up every
  /// ancestor `Scrollable` (crucially, also the screen's outer vertical
  /// `SingleChildScrollView` — the carousel itself can be horizontally
  /// mounted while still sitting below the fold vertically) so it's
  /// actually on-screen, not just present in the tree.
  Future<void> scrollToIngredient(WidgetTester tester, String name) async {
    final target = find.text(name);
    var attempts = 0;
    while (target.evaluate().isEmpty && attempts < 12) {
      await tester.drag(ingredientCarousel, const Offset(-250, 0));
      await tester.pumpAndSettle();
      attempts++;
    }
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
  }

  /// Toggle-category ingredients: the whole card is tappable (unchanged
  /// from before the redesign).
  Future<void> tapIngredientToggle(WidgetTester tester, String name) async {
    await scrollToIngredient(tester, name);
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();
  }

  /// Quantity-category ingredients: taps "Ekle" the first time (quantity
  /// 0 -> 1, no stepper visible yet), the "+" stepper button every time
  /// after (matches `IngredientCard`'s two-affordance design).
  Future<void> tapIngredientAdd(WidgetTester tester, String name) async {
    await scrollToIngredient(tester, name);
    final card = find.ancestor(
      of: find.text(name),
      matching: find.byType(IngredientCard),
    );
    final ekle = find.descendant(of: card, matching: find.text('Ekle'));
    final target = ekle.evaluate().isNotEmpty
        ? ekle
        : find.descendant(of: card, matching: find.byIcon(Icons.add_rounded));
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> tapIngredientRemove(WidgetTester tester, String name) async {
    final card = find.ancestor(
      of: find.text(name),
      matching: find.byType(IngredientCard),
    );
    final target =
        find.descendant(of: card, matching: find.byIcon(Icons.remove_rounded));
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> tapBowluIncele(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(ElevatedButton, 'Bowlu İncele'));
    await tester.pumpAndSettle();
  }

  Future<void> resetBowl(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(TextButton, 'Sıfırla').first);
    await tester.pumpAndSettle();
    final confirmButtons = find.widgetWithText(TextButton, 'Sıfırla');
    if (confirmButtons.evaluate().length > 1) {
      await tester.tap(confirmButtons.last);
      await tester.pumpAndSettle();
    }
  }

  group('1. sihirbaz (wizard) kaldirildi', () {
    testWidgets('hicbir yerde "Adim N/9" metni yoktur', (tester) async {
      await pumpBowlBuilder(tester);

      expect(find.textContaining('Adım'), findsNothing);
      expect(find.textContaining('/9'), findsNothing);
    });

    testWidgets('BuilderProgress agacta bulunmaz', (tester) async {
      await pumpBowlBuilder(tester);

      expect(find.byType(BuilderProgress), findsNothing);
    });

    testWidgets('Geri/Devam Et butonlari yoktur', (tester) async {
      await pumpBowlBuilder(tester);

      expect(find.widgetWithText(OutlinedButton, 'Geri'), findsNothing);
      expect(find.widgetWithText(ElevatedButton, 'Devam Et'), findsNothing);
    });
  });

  group('2. kategori secici', () {
    testWidgets('9 kategoriyi de dogru etiketlerle gosterir', (tester) async {
      await pumpBowlBuilder(tester);

      for (final label in const [
        'Proteinler',
        'Karbonhidratlar',
        'Salatalar',
        'Sebzeler',
        'Meyveler',
        'Turşular',
        'Peynirler',
        'Ekstralar',
        'Soslar',
      ]) {
        if (label != 'Proteinler') {
          var attempts = 0;
          while (find.text(label).evaluate().isEmpty && attempts < 12) {
            await tester.drag(categorySelector, const Offset(-150, 0));
            await tester.pumpAndSettle();
            attempts++;
          }
        }
        expect(find.text(label), findsWidgets, reason: label);
      }
      // "Diğerleri" (the underlying catalog name) never renders — only its
      // customer-facing "Ekstralar" override does.
      expect(find.text('Diğerleri'), findsNothing);
    });

    testWidgets('bir kategoriye dokununca dogrudan o kategoriye gecer', (
      tester,
    ) async {
      await pumpBowlBuilder(tester);

      expect(find.text('Proteinler Seç'), findsOneWidget);

      await tapCategory(tester, 'Salatalar');
      expect(find.text('Salatalar Seç'), findsOneWidget);
    });

    testWidgets(
      'Proteinlerden dogrudan Soslara atlanabilir, aradaki kategorilere ugramadan',
      (tester) async {
        await pumpBowlBuilder(tester);

        expect(find.text('Proteinler Seç'), findsOneWidget);

        await tapCategory(tester, 'Soslar');

        expect(find.text('Soslar Seç'), findsOneWidget);
        // Aradaki hicbir kategori ekranda degil - zorunlu sirali ilerleme yok.
        expect(find.text('Karbonhidratlar Seç'), findsNothing);
        expect(find.text('Salatalar Seç'), findsNothing);
      },
    );
  });

  group('3. statik hero (Bowl Builder Static Hero, 2026-08-08)', () {
    testWidgets(
      'ana duzenleme ekraninda BowlCanvas DEGIL, statik BuildYourBowlHero gorunur',
      (tester) async {
        await pumpBowlBuilder(tester);

        expect(find.byType(BuildYourBowlHero), findsOneWidget);
        expect(find.byType(BowlCanvas), findsNothing);
      },
    );

    testWidgets(
      'statik hero, banners/build_your_bowl_banner.webp yolunu kullanir',
      (tester) async {
        await pumpBowlBuilder(tester);

        final image = tester.widget<Image>(
          find.descendant(
            of: find.byType(BuildYourBowlHero),
            matching: find.byType(Image),
          ),
        );
        expect(
          (image.image as AssetImage).assetName,
          'assets/images/banners/build_your_bowl_banner.webp',
        );
      },
    );

    testWidgets('kategoriler arasinda gecince statik hero monte kalir', (
      tester,
    ) async {
      await pumpBowlBuilder(tester);

      final heroElementBefore = tester.element(find.byType(BuildYourBowlHero));

      await tapCategory(tester, 'Salatalar');

      expect(find.byType(BuildYourBowlHero), findsOneWidget);
      final heroElementAfter = tester.element(find.byType(BuildYourBowlHero));
      expect(identical(heroElementBefore, heroElementAfter), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'banner asset dosyasi henuz yokken bile ekran hatasiz calisir (notr yer tutucu)',
      (tester) async {
        await pumpBowlBuilder(tester);

        // Gercek dosya bu test ortaminda mevcut degil -> errorBuilder devreye
        // girer; ekran cokmemeli ve kirik-resim widget'i gorunmemeli.
        expect(find.byType(BuildYourBowlHero), findsOneWidget);
        expect(find.byType(ErrorWidget), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
        'ozet adiminda hala BowlCanvas kullanilir (bu gorev bunu degistirmedi)',
        (
      tester,
    ) async {
      await pumpBowlBuilder(tester);

      await tapBowluIncele(tester);

      expect(find.text('Bowlu Hazır 🎉'), findsOneWidget);
      expect(find.byType(BowlCanvas), findsOneWidget);
    });
  });

  group('4. canli fiyat/beslenme paneli', () {
    testWidgets('baslangicta 0 TL / 0 kcal / 0 Malzeme gosterir', (
      tester,
    ) async {
      await pumpBowlBuilder(tester);

      // "TL"/"kcal" readouts appear twice (the live dashboard and the
      // compact bottom action bar both show them); "Malzeme"'s bare count
      // only appears in the dashboard.
      expect(find.text('0 TL'), findsWidgets);
      expect(find.text('0 kcal'), findsWidgets);
      expect(find.text('0'), findsOneWidget);
    });

    testWidgets(
        'malzeme secilince fiyat/kalori/protein/malzeme sayisi canli guncellenir',
        (
      tester,
    ) async {
      await pumpBowlBuilder(tester);

      await tapIngredientAdd(tester, 'Izgara Tavuk'); // 40 TL, 165 kcal, 31g

      expect(find.text('40 TL'), findsWidgets);
      expect(find.text('165 kcal'), findsWidgets);
      expect(find.text('31 g'), findsOneWidget);
      // Bare "1" is ambiguous (the ingredient's own stepper also shows its
      // quantity as "1") — assert the count provider directly instead.
      final container = ProviderScope.containerOf(
          tester.element(find.byType(BowlBuilderScreen)));
      expect(
        container.read(bowlBuilderSelectedIngredientCountProvider),
        1,
      );
    });

    testWidgets('miktar (adet) beslenmeyi de fiyat gibi carpar', (
      tester,
    ) async {
      await pumpBowlBuilder(tester);

      await tapIngredientAdd(tester, 'Izgara Tavuk');
      await tapIngredientAdd(tester, 'Izgara Tavuk');
      await tapIngredientAdd(tester, 'Izgara Tavuk');

      expect(find.text('120 TL'), findsWidgets); // 40 * 3
      expect(find.text('495 kcal'), findsWidgets); // 165 * 3
      expect(find.text('93 g'), findsOneWidget); // 31 * 3 protein
      final container = ProviderScope.containerOf(
          tester.element(find.byType(BowlBuilderScreen)));
      // 3 ayri "Ekle"/stepper tiklamasi -> ayni malzemeden 3 adet, bu da
      // bowlBuilderSelectedModifiersProvider'da (ve dolayisiyla sayimda)
      // 3 ayri girdi olarak genisler.
      expect(
        container.read(bowlBuilderSelectedIngredientCountProvider),
        3,
      );
    });
  });

  group('5. Proteinler / Karbonhidratlar - miktar modu', () {
    testWidgets('once "Ekle" ile eklenir, sonra stepper gorunur', (
      tester,
    ) async {
      await pumpBowlBuilder(tester);

      await scrollToIngredient(tester, 'Izgara Tavuk');
      final card = find.ancestor(
        of: find.text('Izgara Tavuk'),
        matching: find.byType(IngredientCard),
      );
      expect(find.descendant(of: card, matching: find.text('Ekle')),
          findsOneWidget);

      await tapIngredientAdd(tester, 'Izgara Tavuk');

      expect(
        find.descendant(of: card, matching: find.byIcon(Icons.add_rounded)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: card,
          matching: find.byIcon(Icons.remove_rounded),
        ),
        findsOneWidget,
      );
    });

    testWidgets('stepper ile arttirinca fiyat price x adet olarak artar', (
      tester,
    ) async {
      await pumpBowlBuilder(tester);

      await tapIngredientAdd(tester, 'Izgara Tavuk');
      expect(find.text('40 TL'), findsWidgets);

      await tapIngredientAdd(tester, 'Izgara Tavuk');
      expect(find.text('80 TL'), findsWidgets);

      await tapIngredientRemove(tester, 'Izgara Tavuk');
      expect(find.text('40 TL'), findsWidgets);
    });

    testWidgets('farkli iki urun ayni anda, sinirsiz sekilde secilebilir', (
      tester,
    ) async {
      await pumpBowlBuilder(tester);

      await tapIngredientAdd(tester, 'Izgara Tavuk');
      await tapIngredientAdd(tester, 'Dana Bonfile');

      final container = ProviderScope.containerOf(
          tester.element(find.byType(BowlBuilderScreen)));
      final state = container.read(bowlBuilderProvider);
      expect(state.quantityFor('bb_protein_izgara_tavuk'), 1);
      expect(state.quantityFor('bb_protein_dana_bonfile'), 1);
      // 40 (Izgara Tavuk) + 150 (Dana Bonfile).
      expect(find.text('190 TL'), findsWidgets);
    });
  });

  group('6. diger kategoriler - toggle modu', () {
    testWidgets('bir porsiyon secilir, tekrar tiklaninca kaldirilir', (
      tester,
    ) async {
      await pumpBowlBuilder(tester);
      await tapCategory(tester, 'Salatalar');

      await tapIngredientToggle(tester, 'Mevsim Salata');
      expect(find.text('15 TL'), findsWidgets);

      await tapIngredientToggle(tester, 'Mevsim Salata');
      expect(find.text('0 TL'), findsWidgets);
    });

    testWidgets('yapay ust sinir yok, birden fazla farkli malzeme secilebilir',
        (
      tester,
    ) async {
      await pumpBowlBuilder(tester);
      await tapCategory(tester, 'Salatalar');

      await tapIngredientToggle(tester, 'Mevsim Salata'); // 15
      await tapIngredientToggle(tester, 'Kıvırcık Marul'); // 15
      await tapIngredientToggle(tester, 'Roka'); // 15
      await tapIngredientToggle(tester, 'Baby Ispanak'); // 30

      final container = ProviderScope.containerOf(
          tester.element(find.byType(BowlBuilderScreen)));
      final state = container.read(bowlBuilderProvider);
      expect(state.quantityFor('bb_salad_mevsim'), 1);
      expect(state.quantityFor('bb_salad_kivircik_marul'), 1);
      expect(state.quantityFor('bb_salad_roka'), 1);
      expect(state.quantityFor('bb_salad_baby_ispanak'), 1);
      expect(find.text('75 TL'), findsWidgets); // 15+15+15+30
    });
  });

  testWidgets(
    'farkli kategoriler arasinda serbestce atlanabilir, secimler her ikisinde de korunur',
    (tester) async {
      await pumpBowlBuilder(tester);

      await tapIngredientAdd(tester, 'Izgara Tavuk');
      await tapCategory(tester, 'Salatalar');
      await tapIngredientToggle(tester, 'Roka');
      await tapCategory(tester, 'Proteinler');

      final container = ProviderScope.containerOf(
          tester.element(find.byType(BowlBuilderScreen)));
      final state = container.read(bowlBuilderProvider);
      expect(state.quantityFor('bb_protein_izgara_tavuk'), 1);
      expect(state.quantityFor('bb_salad_roka'), 1);
    },
  );

  group('7. Bowlu Incele / ozet', () {
    testWidgets('"Bowlu Incele" ozet adimina gecer', (tester) async {
      await pumpBowlBuilder(tester);

      await tapBowluIncele(tester);

      expect(find.text('Bowlu Hazır 🎉'), findsOneWidget);
    });

    testWidgets(
      'hicbir secim yapilmadan da ozete gidilebilir (hicbir kategori zorunlu degil)',
      (tester) async {
        await pumpBowlBuilder(tester);

        await tapBowluIncele(tester);

        expect(find.text('Bowlu Hazır 🎉'), findsOneWidget);
        expect(
          find.widgetWithText(ElevatedButton, 'Sepete Ekle · 0 TL'),
          findsOneWidget,
        );
      },
    );

    testWidgets('ozette de canli beslenme paneli gosterilir', (tester) async {
      await pumpBowlBuilder(tester);

      await tapIngredientAdd(tester, 'Izgara Tavuk');
      await tapBowluIncele(tester);

      expect(find.text('165 kcal'), findsOneWidget);
      expect(find.text('31 g'), findsOneWidget);
    });

    testWidgets(
      'ozet ekrani ayni malzemeden birden fazlasini "x N" ile gosterir',
      (tester) async {
        await pumpBowlBuilder(tester);

        await tapIngredientAdd(tester, 'Izgara Tavuk');
        await tapIngredientAdd(tester, 'Izgara Tavuk');
        await tapIngredientAdd(tester, 'Izgara Tavuk');
        await tapBowluIncele(tester);

        expect(find.text('Izgara Tavuk × 3'), findsOneWidget);
      },
    );

    testWidgets('not ve secimler sepete dogru fiyatla aktarilir', (
      tester,
    ) async {
      await pumpBowlBuilder(tester);

      await tapIngredientAdd(tester, 'Izgara Tavuk'); // 40
      await tapCategory(tester, 'Salatalar');
      await tapIngredientToggle(tester, 'Roka'); // 15
      await tapBowluIncele(tester);

      expect(find.text('Bowlu Hazır 🎉'), findsOneWidget);

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
    });

    testWidgets(
      'hicbir secim yapilmadan urun 0 TL ile sepete eklenebilir',
      (tester) async {
        await pumpBowlBuilder(tester);
        await tapBowluIncele(tester);

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
  });

  group('8. sifirla', () {
    testWidgets('bowl bosken onay istemeden dogrudan sifirlar', (
      tester,
    ) async {
      await pumpBowlBuilder(tester);

      await resetBowl(tester);

      expect(find.text('Bowlu Sıfırla'), findsNothing);
      final container = ProviderScope.containerOf(
          tester.element(find.byType(BowlBuilderScreen)));
      expect(
        container.read(bowlBuilderProvider).selectedQuantitiesByIngredient,
        isEmpty,
      );
    });

    testWidgets('secim varken onay ister ve onaylaninca temizler', (
      tester,
    ) async {
      await pumpBowlBuilder(tester);
      await tapIngredientAdd(tester, 'Izgara Tavuk');

      await tester.tap(find.widgetWithText(TextButton, 'Sıfırla').first);
      await tester.pumpAndSettle();
      expect(find.text('Bowlu Sıfırla'), findsOneWidget);

      final container = ProviderScope.containerOf(
          tester.element(find.byType(BowlBuilderScreen)));
      // Onaylanmadan once secim hala duruyor.
      expect(
        container
            .read(bowlBuilderProvider)
            .quantityFor('bb_protein_izgara_tavuk'),
        1,
      );

      await tester.tap(find.widgetWithText(TextButton, 'Sıfırla').last);
      await tester.pumpAndSettle();

      expect(
        container.read(bowlBuilderProvider).selectedQuantitiesByIngredient,
        isEmpty,
      );
    });

    testWidgets('secim varken "Vazgec" secimi korur', (tester) async {
      await pumpBowlBuilder(tester);
      await tapIngredientAdd(tester, 'Izgara Tavuk');

      await tester.tap(find.widgetWithText(TextButton, 'Sıfırla').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Vazgeç'));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
          tester.element(find.byType(BowlBuilderScreen)));
      expect(
        container
            .read(bowlBuilderProvider)
            .quantityFor('bb_protein_izgara_tavuk'),
        1,
      );
    });
  });

  group('9. yogunluk (responsive)', () {
    testWidgets('daha genis ekranda ayni anda daha fazla kart monte olur', (
      tester,
    ) async {
      await pumpBowlBuilder(tester, viewportSize: const Size(360, 900));
      final narrowCount = find.byType(IngredientCard).evaluate().length;

      await pumpBowlBuilder(tester, viewportSize: const Size(1000, 900));
      final wideCount = find.byType(IngredientCard).evaluate().length;

      expect(wideCount, greaterThan(narrowCount));
    });
  });

  testWidgets(
    'erisilebilirlik / buyuk text scale ile tasma/exception olusmaz',
    (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(1.6),
              ),
              child: child!,
            ),
            home: const BowlBuilderScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tapIngredientAdd(tester, 'Izgara Tavuk');
      expect(tester.takeException(), isNull);

      await tapBowluIncele(tester);
      expect(tester.takeException(), isNull);
    },
  );
}
