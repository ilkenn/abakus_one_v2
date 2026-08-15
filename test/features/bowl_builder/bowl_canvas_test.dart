import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/bowl_builder/data/bowl_builder_catalog.dart';
import 'package:abakus_one_v2/features/bowl_builder/domain/models/bowl_layer_type.dart';
import 'package:abakus_one_v2/features/bowl_builder/presentation/providers/bowl_builder_provider.dart';
import 'package:abakus_one_v2/features/bowl_builder/presentation/widgets/bowl_canvas.dart';

void main() {
  Future<ProviderContainer> pumpCanvas(WidgetTester tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: BowlCanvas()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  int assetImageCount(WidgetTester tester, String assetName) {
    return tester
        .widgetList<Image>(find.byType(Image))
        .where((w) =>
            w.image is AssetImage &&
            (w.image as AssetImage).assetName == assetName)
        .length;
  }

  // Scoped to inside BowlCanvas's own subtree — the wider widget tree also
  // contains unrelated FadeTransitions (route transitions, Material
  // internals), so a bare find.byType(FadeTransition) is ambiguous. Every
  // test using this selects exactly one ingredient, so exactly one
  // FadeTransition (that ingredient's own overlay) exists in this scope.
  Finder soleLayerFadeTransition() {
    return find.descendant(
      of: find.byType(BowlCanvas),
      matching: find.byType(FadeTransition),
    );
  }

  testWidgets(
    'bowl taban gorseli tam olarak bir kez render edilir, hic secim yokken bile',
    (tester) async {
      await pumpCanvas(tester);

      expect(
        assetImageCount(tester, 'assets/images/bowl/bowl_empty.png'),
        1,
      );
      // Henuz gercek bowl_empty.png yok -> notr bir "bowl" siluet
      // ciziliyor (CustomPaint), jenerik bir yemek ikonu degil, kirik-
      // resim ikonu hic degil.
      expect(find.byIcon(Icons.ramen_dining_rounded), findsNothing);
      expect(find.byType(Icon), findsNothing);
      expect(find.byType(CustomPaint), findsWidgets);
      expect(find.byType(ErrorWidget), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'ayni malzeme birden fazla kez eklense de kendi katmaninda sadece bir kez gorsel denenir',
    (tester) async {
      final container = await pumpCanvas(tester);

      container.read(bowlBuilderProvider.notifier)
        ..incrementIngredient('bb_protein_izgara_tavuk')
        ..incrementIngredient('bb_protein_izgara_tavuk')
        ..incrementIngredient('bb_protein_izgara_tavuk');
      await tester.pumpAndSettle();

      expect(
        assetImageCount(
          tester,
          'assets/images/bowl/layers/izgara_tavuk.png',
        ),
        1,
      );
      // Bowl hala tek.
      expect(
        assetImageCount(tester, 'assets/images/bowl/bowl_empty.png'),
        1,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'farkli kategorilerdeki secimler dogru katmanin RepaintBoundary altinda render edilir',
    (tester) async {
      final container = await pumpCanvas(tester);

      container.read(bowlBuilderProvider.notifier)
        ..incrementIngredient('bb_protein_izgara_tavuk') // protein
        ..toggleIngredient('bb_vegetable_domates') // vegetable
        ..toggleIngredient('bb_cheese_beyaz'); // cheese
      await tester.pumpAndSettle();

      final proteinLayer = find.descendant(
        of: find.byKey(const ValueKey(BowlLayerType.protein)),
        matching: find.byType(Image),
      );
      expect(proteinLayer, findsOneWidget);
      expect(
        (tester.widget<Image>(proteinLayer).image as AssetImage).assetName,
        'assets/images/bowl/layers/izgara_tavuk.png',
      );

      final vegetableLayer = find.descendant(
        of: find.byKey(const ValueKey(BowlLayerType.vegetable)),
        matching: find.byType(Image),
      );
      expect(vegetableLayer, findsOneWidget);
      expect(
        (tester.widget<Image>(vegetableLayer).image as AssetImage).assetName,
        'assets/images/bowl/layers/domates.png',
      );

      final cheeseLayer = find.descendant(
        of: find.byKey(const ValueKey(BowlLayerType.cheese)),
        matching: find.byType(Image),
      );
      expect(cheeseLayer, findsOneWidget);
      expect(
        (tester.widget<Image>(cheeseLayer).image as AssetImage).assetName,
        'assets/images/bowl/layers/beyaz_peynir.png',
      );

      // Bos kalan katmanlar (base/sauce/topping) hicbir Image render etmez.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey(BowlLayerType.sauce)),
          matching: find.byType(Image),
        ),
        findsNothing,
      );

      expect(tester.takeException(), isNull);
    },
  );

  group('disaridan verilen ingredient listesi (Faz 8.3, Cart onizlemesi)', () {
    testWidgets(
      'ingredients verilince bowlBuilderProvider yerine o liste render edilir',
      (tester) async {
        const repository = LocalBowlBuilderCatalogRepository();
        final tofu = repository.ingredientById('bb_protein_tofu')!;

        final container = ProviderContainer();
        addTearDown(container.dispose);
        // Canli builder state'i BOS birakildi, hicbir sey secilmedi -
        // yine de disaridan verilen liste render edilmeli.
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: Scaffold(body: BowlCanvas(ingredients: [tofu])),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          assetImageCount(tester, 'assets/images/bowl/layers/tofu.png'),
          1,
        );
        expect(
          container.read(bowlBuilderProvider).selectedQuantitiesByIngredient,
          isEmpty,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'disaridan verilen liste ilk render de animasyonsuz, tam opaklikta gorunur',
      (tester) async {
        const repository = LocalBowlBuilderCatalogRepository();
        final ingredient = repository.ingredientById('bb_protein_tofu')!;

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(body: BowlCanvas(ingredients: [ingredient])),
            ),
          ),
        );
        // Tek bir frame - pumpAndSettle degil - ilk render aninda bile
        // tam opaklikta olmali (Cart'ta her acilista "yeniden eklenmis"
        // gibi gorunmemeli).
        await tester.pump();

        final fade = tester.widget<FadeTransition>(
          soleLayerFadeTransition(),
        );
        expect(fade.opacity.value, 1.0);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('katman animasyonlari (Faz 8.3)', () {
    testWidgets(
      'yeni secilen malzeme fade+scale ile aninda degil, animasyonla belirir',
      (tester) async {
        final container = await pumpCanvas(tester);

        container
            .read(bowlBuilderProvider.notifier)
            .toggleIngredient('bb_vegetable_domates');
        await tester.pump();
        // Animasyonun tam ortasinda (220ms'lik giris animasyonunun
        // yaklasik yarisi) opaklik ne 0 ne 1 olmali.
        await tester.pump(const Duration(milliseconds: 100));

        final fade = tester.widget<FadeTransition>(
          soleLayerFadeTransition(),
        );
        expect(fade.opacity.value, greaterThan(0.0));
        expect(fade.opacity.value, lessThan(1.0));

        await tester.pumpAndSettle();
        final settled = tester.widget<FadeTransition>(
          soleLayerFadeTransition(),
        );
        expect(settled.opacity.value, 1.0);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'kaldirilan malzeme aninda degil, fade+scale ile kaybolur',
      (tester) async {
        final container = await pumpCanvas(tester);

        container
            .read(bowlBuilderProvider.notifier)
            .toggleIngredient('bb_vegetable_domates');
        await tester.pumpAndSettle();
        expect(
          assetImageCount(tester, 'assets/images/bowl/layers/domates.png'),
          1,
        );

        container
            .read(bowlBuilderProvider.notifier)
            .toggleIngredient('bb_vegetable_domates');
        await tester.pump();
        // Cikis animasyonunun ortasinda gorsel hala agactadir (kaybolmadan
        // once soluklasiyor).
        await tester.pump(const Duration(milliseconds: 80));
        expect(
          assetImageCount(tester, 'assets/images/bowl/layers/domates.png'),
          1,
        );

        await tester.pumpAndSettle();
        expect(
          assetImageCount(tester, 'assets/images/bowl/layers/domates.png'),
          0,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'adet degisimi mevcut malzemenin animasyonunu yeniden baslatmaz',
      (tester) async {
        final container = await pumpCanvas(tester);

        container
            .read(bowlBuilderProvider.notifier)
            .incrementIngredient('bb_protein_izgara_tavuk');
        await tester.pumpAndSettle();

        final settledFade = tester.widget<FadeTransition>(
          soleLayerFadeTransition(),
        );
        expect(settledFade.opacity.value, 1.0);

        container
            .read(bowlBuilderProvider.notifier)
            .incrementIngredient('bb_protein_izgara_tavuk');
        // Adet 1 -> 2 sadece fiyati etkiler; ayni tek frame'de bile
        // opaklik dusmemeli (animasyon yeniden tetiklenmedi).
        await tester.pump();

        final afterQuantityChange = tester.widget<FadeTransition>(
          soleLayerFadeTransition(),
        );
        expect(afterQuantityChange.opacity.value, 1.0);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
