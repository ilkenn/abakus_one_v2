import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/core/theme/app_colors.dart';
import 'package:abakus_one_v2/features/bowl_builder/presentation/providers/bowl_builder_provider.dart';
import 'package:abakus_one_v2/features/bowl_builder/presentation/screens/bowl_builder_screen.dart';
import 'package:abakus_one_v2/features/bowl_builder/presentation/widgets/bowl_builder_live_metrics.dart';
import 'package:abakus_one_v2/features/bowl_builder/presentation/widgets/bowl_canvas.dart';
import 'package:abakus_one_v2/features/bowl_builder/presentation/widgets/build_your_bowl_hero.dart';
import 'package:abakus_one_v2/features/bowl_builder/presentation/widgets/builder_progress.dart';
import 'package:abakus_one_v2/features/bowl_builder/presentation/widgets/ingredient_card.dart';
import 'package:abakus_one_v2/features/cart/presentation/providers/cart_provider.dart';
import 'package:abakus_one_v2/shared/widgets/cards/app_card.dart';

void main() {
  /// Phone-sized by default. [textScale] > 1.0 applies a `MediaQuery`
  /// override, matching the app's own large-accessibility-text-scale
  /// tests (B.4: extracted here so overflow/extreme-value tests don't
  /// each need to hand-roll the `MaterialApp(builder: ...)` wiring).
  Future<void> pumpBowlBuilder(
    WidgetTester tester, {
    Size viewportSize = const Size(400, 900),
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = viewportSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          builder: textScale == 1.0
              ? null
              : (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(textScale)),
                    child: child!,
                  ),
          home: const BowlBuilderScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Same screen, but reached via a real `Navigator.push` from a
  /// placeholder host route — needed only for the B.3.4 AppBar-back tests,
  /// where the whole point is distinguishing "popped `BowlBuilderScreen`
  /// back to whatever pushed it" from "stayed on `BowlBuilderScreen`, just
  /// moved to a different internal step." `pumpBowlBuilder`'s bare
  /// `MaterialApp(home: ...)` can't tell those apart — it's the only route,
  /// so there's nothing to pop back to.
  Future<void> pumpBowlBuilderPushed(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const BowlBuilderScreen(),
                    ),
                  ),
                  child: const Text('Bowl Builder Aç'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bowl Builder Aç'));
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

  /// The "Seçilen Malzemeler" `AppCard` on the review step — category
  /// names (e.g. "Salatalar") also appear as chips in the always-visible
  /// category selector at the top of the screen, so tests asserting a
  /// category header is/isn't present must scope their search to this
  /// card specifically, not the whole screen.
  Finder selectedIngredientsCard() => find.ancestor(
        of: find.text('Seçilen Malzemeler'),
        matching: find.byType(AppCard),
      );

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
        'ozet adiminda artik BowlCanvas kullanilmaz (B.3 — gorsel onizleme '
        'iptal edildi)', (
      tester,
    ) async {
      await pumpBowlBuilder(tester);

      await tapBowluIncele(tester);

      expect(find.text('Sipariş Özeti'), findsOneWidget);
      expect(find.byType(BowlCanvas), findsNothing);
    });
  });

  group('4. sabitlenmis (pinned) ozet - secim sirasinda (B.1)', () {
    // LOCKED B.1 decision: during picking, BowlBuilderActionBar's pinned
    // price/kcal/protein readout is the ONLY nutrition summary on screen
    // — the full BowlBuilderLiveMetrics dashboard (Fiyat/Kalori/Protein/
    // Yağ/Karbonhidrat/Malzeme) no longer renders on any picking step at
    // all, only on the review/summary step (group 7).

    testWidgets(
        'secim adiminda tam BowlBuilderLiveMetrics paneli agacta yoktur', (
      tester,
    ) async {
      await pumpBowlBuilder(tester);

      expect(find.byType(BowlBuilderLiveMetrics), findsNothing);
      // Panelin kendine ozgu etiketleri de hicbir yerde gorunmez.
      expect(find.text('Malzeme'), findsNothing);
      expect(find.text('Yağ'), findsNothing);
      expect(find.text('Karbonhidrat'), findsNothing);
    });

    testWidgets('baslangicta pinned ozet 0 TL / 0 kcal / 0 g protein gosterir',
        (tester) async {
      await pumpBowlBuilder(tester);

      // Artik tek yerde (pinned action bar) gosteriliyor — tam olarak bir
      // kez.
      expect(find.text('0 TL'), findsOneWidget);
      expect(find.text('0 kcal'), findsOneWidget);
      expect(find.text('0 g protein'), findsOneWidget);
    });

    testWidgets(
        'malzeme secilince pinned fiyat/kalori/protein canli guncellenir', (
      tester,
    ) async {
      await pumpBowlBuilder(tester);

      await tapIngredientAdd(tester, 'Izgara Tavuk'); // 40 TL, 165 kcal, 31g

      expect(find.text('40 TL'), findsOneWidget);
      expect(find.text('165 kcal'), findsOneWidget);
      expect(find.text('31 g protein'), findsOneWidget);
      // Malzeme sayisi artik hicbir UI metninde gorunmuyor (sadece ozet
      // adiminda) — provider'i dogrudan okuyarak dogruluyoruz.
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

      expect(find.text('120 TL'), findsOneWidget); // 40 * 3
      expect(find.text('495 kcal'), findsOneWidget); // 165 * 3
      expect(find.text('93 g protein'), findsOneWidget); // 31 * 3 protein
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

      expect(find.text('Sipariş Özeti'), findsOneWidget);
    });

    testWidgets(
      'hicbir secim yapilmadan da ozete gidilebilir (hicbir kategori zorunlu degil)',
      (tester) async {
        await pumpBowlBuilder(tester);

        await tapBowluIncele(tester);

        expect(find.text('Sipariş Özeti'), findsOneWidget);
        expect(
          find.widgetWithText(ElevatedButton, 'Sepete Ekle · 0 TL'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
        'ozette tek bir makro ozet karti gosterilir (Fiyat/Kalori/Protein/'
        'Yağ/Karbonhidrat) — B.3: BowlBuilderLiveMetrics artik kullanilmaz',
        (tester) async {
      await pumpBowlBuilder(tester);

      await tapIngredientAdd(tester, 'Izgara Tavuk'); // 40 TL, 165 kcal,
      // 31g protein, 4g yağ, 0g karbonhidrat
      await tapBowluIncele(tester);

      // B.1'de picking'te kullanilan eski dashboard widget'i — B.3'te
      // ozette de artik kullanilmiyor, tamamen orphan.
      expect(find.byType(BowlBuilderLiveMetrics), findsNothing);

      // "40 TL" appears twice by design (Fiyat in the macro card, Toplam
      // in the quantity/note card below — both correctly equal at
      // quantity 1) — assert presence, not an exact single occurrence.
      expect(find.text('40 TL'), findsWidgets);
      expect(find.text('165 kcal'), findsOneWidget);
      expect(find.text('31 g'), findsOneWidget); // Protein
      expect(find.text('4 g'), findsOneWidget); // Yağ
      expect(find.text('0 g'), findsOneWidget); // Karbonhidrat
      expect(find.text('Fiyat'), findsOneWidget);
      expect(find.text('Kalori'), findsOneWidget);
      expect(find.text('Protein'), findsOneWidget);
      expect(find.text('Yağ'), findsOneWidget);
      expect(find.text('Karbonhidrat'), findsOneWidget);
      // B.3: ingredient count ("Malzeme") artik makro kartta gosterilmiyor
      // — Seçilen Malzemeler bölümü her secimi zaten tek tek listeliyor.
      expect(find.text('Malzeme'), findsNothing);
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

      expect(find.text('Sipariş Özeti'), findsOneWidget);

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
      'hicbir secim yapilmadan Sepete Ekle CTA devre disidir (B.3.2 — '
      'artik bos bowl sepete eklenemez)',
      (tester) async {
        await pumpBowlBuilder(tester);
        await tapBowluIncele(tester);

        final context = tester.element(find.byType(BowlBuilderScreen));
        final container = ProviderScope.containerOf(context);

        final cta = tester.widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'Sepete Ekle · 0 TL'),
        );
        expect(cta.onPressed, isNull);

        // Devre disi bir butona dokunmak hicbir sey yapmamali.
        await tester.tap(
          find.widgetWithText(ElevatedButton, 'Sepete Ekle · 0 TL'),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();

        expect(container.read(cartProvider), isEmpty);
      },
    );

    testWidgets(
      'en az bir malzeme secilince Sepete Ekle CTA tekrar aktif olur',
      (tester) async {
        await pumpBowlBuilder(tester);
        await tapIngredientAdd(tester, 'Izgara Tavuk');
        await tapBowluIncele(tester);

        final cta = tester.widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'Sepete Ekle · 40 TL'),
        );
        expect(cta.onPressed, isNotNull);
      },
    );
  });

  group('12. B.3 - bilgi odakli ozet ekrani', () {
    testWidgets('tek bir makro ozet karti var, ikinci bir kopyasi yok', (
      tester,
    ) async {
      await pumpBowlBuilder(tester);

      await tapIngredientAdd(tester, 'Izgara Tavuk');
      await tapBowluIncele(tester);

      // Her makro alanin etiketi ozet ekraninda tam olarak bir kez
      // gorunur — ikinci bir (kopya) ozet karti yok.
      expect(find.text('Fiyat'), findsOneWidget);
      expect(find.text('Kalori'), findsOneWidget);
      expect(find.text('Protein'), findsOneWidget);
      expect(find.text('Yağ'), findsOneWidget);
      expect(find.text('Karbonhidrat'), findsOneWidget);
    });

    testWidgets(
        'Alerjenler bolumu gorunur, veri mevcut olmadigini acikca belirtir '
        '(B.3.1 — UNKNOWN != CONFIRMED_NONE, BowlBuilderIngredient henuz '
        'allergen alani tasimiyor)', (tester) async {
      await pumpBowlBuilder(tester);

      // Bos secimle de, gercek bir secimle de — katalogdaki hicbir
      // malzemenin alerjen verisi yok, bu yuzden ikisinde de "veri henuz
      // yok" durumu gosterilir; hicbir zaman "alerjen yok" gibi yanlis
      // bir guven veren mesaj ya da uydurma bir alerjen etiketi cikmaz.
      await tapBowluIncele(tester);
      expect(find.text('Alerjenler'), findsOneWidget);
      expect(find.text('Alerjen bilgisi henüz mevcut değil'), findsOneWidget);
      expect(
        find.text(
          'İçerik ve alerjen bilgileri tamamlandığında burada gösterilecek.',
        ),
        findsOneWidget,
      );
      // Locked: these must never appear, in either state.
      expect(find.text('Bilinen alerjen bulunmuyor'), findsNothing);
      expect(find.text('Alerjen yok'), findsNothing);

      await tester.tap(find.widgetWithText(TextButton, 'Sıfırla').first);
      await tester.pumpAndSettle();
      await tapIngredientAdd(tester, 'Izgara Tavuk');
      await tapBowluIncele(tester);
      expect(find.text('Alerjen bilgisi henüz mevcut değil'), findsOneWidget);
      expect(find.text('Bilinen alerjen bulunmuyor'), findsNothing);
      expect(find.text('Alerjen yok'), findsNothing);
    });

    testWidgets('sadece secilen malzemeler Seçilen Malzemeler altinda gorunur',
        (tester) async {
      await pumpBowlBuilder(tester);

      await tapIngredientAdd(tester, 'Izgara Tavuk');
      await tapBowluIncele(tester);

      expect(find.text('Izgara Tavuk'), findsOneWidget);
      // Ayni kategoride secilmeyen baska bir malzeme gorunmemeli.
      expect(find.text('Dana Bonfile'), findsNothing);
    });

    testWidgets('bos kategoriler Seçilen Malzemeler altinda gosterilmez', (
      tester,
    ) async {
      await pumpBowlBuilder(tester);

      await tapIngredientAdd(tester, 'Izgara Tavuk'); // Proteinler
      await tapBowluIncele(tester);

      // Sadece secim yapilan kategori (Proteinler) basligi gorunur;
      // hicbir secim yapilmayan kategoriler icin bos bir baslik/bolum
      // render edilmez. Kategori adlari ustteki secici cip'lerinde de
      // gorundugu icin arama, Seçilen Malzemeler kartiyla sinirlaniyor.
      final card = selectedIngredientsCard();
      expect(
        find.descendant(of: card, matching: find.text('Proteinler')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('Salatalar')),
        findsNothing,
      );
      expect(
        find.descendant(of: card, matching: find.text('Meyveler')),
        findsNothing,
      );
      expect(
        find.descendant(of: card, matching: find.text('Soslar')),
        findsNothing,
      );
    });

    testWidgets(
        'birden fazla kategoriden secim yapilinca her ikisi de kendi '
        'basligi altinda gorunur', (tester) async {
      await pumpBowlBuilder(tester);

      await tapIngredientAdd(tester, 'Izgara Tavuk'); // Proteinler
      await tapCategory(tester, 'Salatalar');
      await tapIngredientToggle(tester, 'Roka'); // Salatalar
      await tapBowluIncele(tester);

      final card = selectedIngredientsCard();
      expect(
        find.descendant(of: card, matching: find.text('Proteinler')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('Salatalar')),
        findsOneWidget,
      );
      expect(find.text('Izgara Tavuk'), findsOneWidget);
      expect(find.text('Roka'), findsOneWidget);
    });

    testWidgets('Adet stepper ozet ekraninda calisir, Toplam guncellenir', (
      tester,
    ) async {
      await pumpBowlBuilder(tester);

      await tapIngredientAdd(tester, 'Izgara Tavuk'); // 40 TL
      await tapBowluIncele(tester);

      expect(find.text('1'), findsWidgets);

      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();

      expect(find.text('3'), findsOneWidget);
      // Adet 3 -> Toplam = 40 * 3 = 120 TL.
      expect(
        find.widgetWithText(ElevatedButton, 'Sepete Ekle · 120 TL'),
        findsOneWidget,
      );
    });

    testWidgets('375px telefon genisliginde tasma/exception olusmaz', (
      tester,
    ) async {
      await pumpBowlBuilder(tester, viewportSize: const Size(375, 812));

      await tapIngredientAdd(tester, 'Izgara Tavuk');
      await tapCategory(tester, 'Salatalar');
      await tapIngredientToggle(tester, 'Roka');
      await tapBowluIncele(tester);

      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'uzun malzeme adi + 1.6x text scale ile ozet ekraninda tasma/'
        'exception olusmaz', (tester) async {
      tester.view.physicalSize = const Size(375, 812);
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

      await tapCategory(tester, 'Karbonhidratlar');
      await tapIngredientAdd(tester, 'Beyaz + Siyah Basmati Karışımı');
      await tapBowluIncele(tester);

      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'kategori secici sadece secim asamasinda gorunur, ozet ekraninda '
        'gizlenir (B.3.3)', (tester) async {
      await pumpBowlBuilder(tester);

      // Secim asamasinda: kategori secici gorunur.
      expect(categorySelector, findsOneWidget);

      await tapIngredientAdd(tester, 'Izgara Tavuk');
      await tapBowluIncele(tester);

      // Ozet asamasinda: kategori secici artik render edilmiyor —
      // musteri artik secim yapmiyor, bu satir sadece dikey alan
      // kaplardi. Secilen Malzemeler altindaki kategori gruplamasi
      // (catalog.categories'ten geliyor) bundan etkilenmez, ayrica
      // dogrulanir.
      expect(categorySelector, findsNothing);
      final card = selectedIngredientsCard();
      expect(
        find.descendant(of: card, matching: find.text('Proteinler')),
        findsOneWidget,
      );

      await resetBowl(tester);

      // Sifirlama secim asamasina donuyor: kategori secici tekrar gorunur.
      expect(categorySelector, findsOneWidget);
    });
  });

  group('13. B.3.4 - ozet ekranindan duzenlemeye donus', () {
    testWidgets('"Seçimleri Düzenle" butonu ozet ekraninda gorunur', (
      tester,
    ) async {
      await pumpBowlBuilder(tester);

      await tapIngredientAdd(tester, 'Izgara Tavuk');
      await tapBowluIncele(tester);

      expect(find.byKey(const Key('editSelectionsButton')), findsOneWidget);
      expect(find.text('Seçimleri Düzenle'), findsOneWidget);
    });

    testWidgets(
        '"Seçimleri Düzenle" tiklaninca secim asamasina doner, kategori '
        'secici tekrar gorunur, secimler korunur', (tester) async {
      await pumpBowlBuilder(tester);

      await tapIngredientAdd(tester, 'Izgara Tavuk');
      await tapBowluIncele(tester);
      expect(categorySelector, findsNothing);

      await tester.tap(find.byKey(const Key('editSelectionsButton')));
      await tester.pumpAndSettle();

      // Secim asamasina donuldu: kategori secici tekrar gorunur, senteti
      // "ozet" sekmesi degil gercek bir kategori aktif.
      expect(categorySelector, findsOneWidget);
      expect(
        find.widgetWithText(ElevatedButton, 'Bowlu İncele'),
        findsOneWidget,
      );

      // Secim silinmedi: tekrar ozete gidince ayni malzeme hala listede.
      await tapBowluIncele(tester);
      final card = selectedIngredientsCard();
      expect(
        find.descendant(of: card, matching: find.text('Izgara Tavuk')),
        findsOneWidget,
      );
    });

    testWidgets('duzenlemeye donus, adet ve siparis notunu da korur', (
      tester,
    ) async {
      await pumpBowlBuilder(tester);

      await tapIngredientAdd(tester, 'Izgara Tavuk');
      await tapBowluIncele(tester);

      await tester.tap(find.byIcon(Icons.add_rounded).first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Az baharatlı olsun');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('editSelectionsButton')));
      await tester.pumpAndSettle();
      await tapBowluIncele(tester);

      expect(find.text('2'), findsOneWidget);
      expect(find.text('Az baharatlı olsun'), findsOneWidget);
    });

    testWidgets(
        'AppBar geri tusu, secim asamasindayken ekrani kapatir (mevcut '
        'davranis degismedi)', (tester) async {
      await pumpBowlBuilderPushed(tester);
      expect(find.byType(BowlBuilderScreen), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();

      // Ekran tamamen kapandi, onu acan sayfaya donuldu.
      expect(find.byType(BowlBuilderScreen), findsNothing);
      expect(find.text('Bowl Builder Aç'), findsOneWidget);
    });

    testWidgets(
        'AppBar geri tusu, ozet ekranindayken ekrani kapatmaz — secim '
        'asamasina doner (B.3.4)', (tester) async {
      await pumpBowlBuilderPushed(tester);

      await tapIngredientAdd(tester, 'Izgara Tavuk');
      await tapBowluIncele(tester);
      expect(categorySelector, findsNothing);

      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();

      // Ekran hala acik — sadece secim asamasina donuldu, route pop
      // edilmedi.
      expect(find.byType(BowlBuilderScreen), findsOneWidget);
      expect(find.text('Bowl Builder Aç'), findsNothing);
      expect(categorySelector, findsOneWidget);

      // Secim korunmus.
      await tapBowluIncele(tester);
      final card = selectedIngredientsCard();
      expect(
        find.descendant(of: card, matching: find.text('Izgara Tavuk')),
        findsOneWidget,
      );
    });
  });

  group('14. B.4 - CTA/dokunma/erisilebilirlik/uc durum cilasi', () {
    testWidgets(
        'secim asamasindaki sabitlenmis fiyat/kalori/protein satirinin her '
        'biri hangi degeri gosterdigini soyleyen ayri bir Semantics '
        'etiketine sahiptir', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpBowlBuilder(tester);

      await tapIngredientAdd(tester, 'Izgara Tavuk');

      expect(find.bySemanticsLabel('Toplam fiyat: 40 TL'), findsOneWidget);
      expect(find.bySemanticsLabel('Toplam kalori: 165 kcal'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Toplam protein: 31 g protein'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets(
        'ozet ekranindaki makro kartinin her alani hangi degeri gosterdigini '
        'soyleyen ayri bir Semantics etiketine sahiptir', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpBowlBuilder(tester);

      await tapIngredientAdd(tester, 'Izgara Tavuk');
      await tapBowluIncele(tester);

      expect(find.bySemanticsLabel('Fiyat: 40 TL'), findsOneWidget);
      expect(find.bySemanticsLabel('Kalori: 165 kcal'), findsOneWidget);
      expect(find.bySemanticsLabel('Protein: 31 g'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('ozet ekranindaki Adet stepper butonlari tooltip tasir', (
      tester,
    ) async {
      await pumpBowlBuilder(tester);

      await tapIngredientAdd(tester, 'Izgara Tavuk');
      await tapBowluIncele(tester);

      expect(find.byTooltip('Adet azalt'), findsOneWidget);
      expect(find.byTooltip('Adet arttır'), findsOneWidget);
    });

    testWidgets(
        'yuksek adet/fiyat/makro degerleriyle 375px + 1.6x text scale '
        'altinda secim asamasinda tasma/exception olusmaz', (tester) async {
      await pumpBowlBuilder(
        tester,
        viewportSize: const Size(375, 812),
        textScale: 1.6,
      );

      // Ayni malzemeyi cok kez ekleyerek fiyat/kalori/protein degerlerini
      // 3-4 haneli sayilara sisiriyoruz — sabitlenmis satirin (Fiyat/
      // Kalori/Protein + Bowlu İncele) yine de tasmadigini dogrulamak icin.
      for (var i = 0; i < 20; i++) {
        await tapIngredientAdd(tester, 'Izgara Tavuk');
      }

      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'yuksek adet/fiyat/makro degerleri + uzun siparis notuyla 375px + '
        '1.6x text scale altinda ozet ekraninda tasma/exception olusmaz', (
      tester,
    ) async {
      await pumpBowlBuilder(
        tester,
        viewportSize: const Size(375, 812),
        textScale: 1.6,
      );

      for (var i = 0; i < 20; i++) {
        await tapIngredientAdd(tester, 'Izgara Tavuk');
      }
      await tapBowluIncele(tester);

      // Adet'i de arttirarak Toplam/Birim fiyat satirini da devreye sokuyor,
      // 200 karakterlik siparis notu (maxLength sinirinin tamami) giriyoruz.
      // 1.6x scale + uzun secim listesi ekrani epey uzattigi icin, once
      // kaydirarak butonu gercekten gorunur hale getiriyoruz.
      final addButton = find.byIcon(Icons.add_rounded).first;
      await tester.ensureVisible(addButton);
      await tester.pumpAndSettle();
      await tester.tap(addButton);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'Ç' * 200,
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
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

  group('10. kompakt hero + fold-ustu ilk malzeme (B.1)', () {
    testWidgets('375px genislikte hero yukseklik hedef araliginda (110-140px)',
        (tester) async {
      await pumpBowlBuilder(tester, viewportSize: const Size(375, 812));

      final heroSize = tester.getSize(find.byType(BuildYourBowlHero));
      expect(heroSize.height, inInclusiveRange(110.0, 140.0));
    });

    testWidgets(
        '375x812 ekranda ilk malzeme sirasi ek kaydirma olmadan buyuk '
        'olcude gorunur durumdadir', (tester) async {
      await pumpBowlBuilder(tester, viewportSize: const Size(375, 812));

      // Hicbir ek kaydirma yapilmadan — sadece ilk pump/pumpAndSettle
      // sonrasi — malzeme satirinin ust kenari, 812px'lik goruntu
      // alaninin buyuk kismi icinde kalmali (eski tasarimda hero + tam
      // beslenme paneli bu noktayi ekranin cok altina itiyordu).
      final carouselRect = tester.getRect(ingredientCarousel);
      expect(carouselRect.top, lessThan(400));
      // En az bir gercek IngredientCard, ek kaydirma olmadan zaten monte
      // ve goruntu alani icinde.
      expect(find.byType(IngredientCard), findsWidgets);
    });
  });

  group('11. kompakt kart + kaydirma kesfedilebilirligi (B.2)', () {
    testWidgets(
        'kart genisligi 145-155px araliginda, satir yuksekligi 400\'e '
        'gore belirgin sekilde kisaltilmis (<=260px)', (tester) async {
      await pumpBowlBuilder(tester, viewportSize: const Size(375, 812));

      final cardSize = tester.getSize(find.byType(IngredientCard).first);
      expect(cardSize.width, inInclusiveRange(145.0, 155.0));

      final rowSize = tester.getSize(ingredientCarousel);
      expect(rowSize.height, lessThanOrEqualTo(260));
    });

    testWidgets('secili durum acik sekilde farklidir (subtle olive yuzey)', (
      tester,
    ) async {
      await pumpBowlBuilder(tester);
      await tapCategory(tester, 'Salatalar');

      final card = find.ancestor(
        of: find.text('Mevsim Salata'),
        matching: find.byType(IngredientCard),
      );
      final decorationBefore = tester
          .widget<AnimatedContainer>(
            find
                .descendant(of: card, matching: find.byType(AnimatedContainer))
                .first,
          )
          .decoration as BoxDecoration;
      expect(decorationBefore.color, AppColors.surface);

      await tapIngredientToggle(tester, 'Mevsim Salata');

      final decorationAfter = tester
          .widget<AnimatedContainer>(
            find
                .descendant(of: card, matching: find.byType(AnimatedContainer))
                .first,
          )
          .decoration as BoxDecoration;
      expect(decorationAfter.color, AppColors.primaryExtraLight);
      expect(decorationAfter.border?.top.color, AppColors.primary);
    });

    testWidgets(
        '375px genislikte bir sonraki kart kismen gorunur '
        '(discoverability icin)', (tester) async {
      await pumpBowlBuilder(tester, viewportSize: const Size(375, 812));

      // 150px kart + 12px ayirici ile 327px'lik icerik genisligine tam 2
      // kart sigar; kaydirma kesfedilebilirligi icin en az bir kismi
      // gorunen 3. kart da monte olmus olmali.
      expect(find.byType(IngredientCard).evaluate().length, greaterThan(2));
    });

    testWidgets('satir basinda sadece sag ok gorunur, sol ok yoktur', (
      tester,
    ) async {
      await pumpBowlBuilder(tester);

      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
      expect(find.byIcon(Icons.chevron_left_rounded), findsNothing);
    });

    testWidgets('kaydirdiktan sonra sol ok gorunur hale gelir', (
      tester,
    ) async {
      await pumpBowlBuilder(tester);

      await tester.drag(ingredientCarousel, const Offset(-250, 0));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.chevron_left_rounded), findsOneWidget);
    });

    testWidgets('sag ok tiklamasi malzeme ListView\'ini gercekten kaydirir', (
      tester,
    ) async {
      await pumpBowlBuilder(tester);

      ScrollableState scrollableOf(Finder within) =>
          tester.state<ScrollableState>(
            find
                .descendant(of: within, matching: find.byType(Scrollable))
                .first,
          );

      final before = scrollableOf(ingredientCarousel).position.pixels;
      expect(before, 0);

      await tester.tap(find.byIcon(Icons.chevron_right_rounded));
      await tester.pumpAndSettle();

      final after = scrollableOf(ingredientCarousel).position.pixels;
      expect(after, greaterThan(before + 100));
    });

    testWidgets(
        'uzun malzeme adi + 1.6x text scale ile tasma/exception olusmaz', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(375, 812);
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

      await tapCategory(tester, 'Karbonhidratlar');
      await scrollToIngredient(tester, 'Beyaz + Siyah Basmati Karışımı');

      expect(tester.takeException(), isNull);
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
