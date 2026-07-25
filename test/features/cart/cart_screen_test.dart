import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/bowl_builder/presentation/widgets/bowl_canvas.dart';
import 'package:abakus_one_v2/features/cart/presentation/providers/cart_provider.dart';
import 'package:abakus_one_v2/features/cart/presentation/screens/cart_screen.dart';
import 'package:abakus_one_v2/features/menu/domain/models/selected_modifier.dart';

void main() {
  Future<ProviderContainer> pumpCart(WidgetTester tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: CartScreen()),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets(
    'custom bowl satirinda kucuk BowlCanvas onizlemesi gosterilir',
    (tester) async {
      final container = await pumpCart(tester);

      container.read(cartProvider.notifier).addToCart(
        id: 'custom_bowl_123',
        name: 'Kendi Bowlun',
        desc: 'Izgara Tavuk',
        price: 0,
        selectedModifiers: const [
          SelectedModifier(
            groupId: 'protein',
            groupName: 'Proteinler',
            optionId: 'bb_protein_izgara_tavuk',
            optionName: 'Izgara Tavuk',
            extraPrice: 40,
          ),
        ],
      );
      await tester.pumpAndSettle();

      expect(find.byType(BowlCanvas), findsOneWidget);
    },
  );

  testWidgets(
    'normal menu urununde BowlCanvas onizlemesi gosterilmez',
    (tester) async {
      final container = await pumpCart(tester);

      container.read(cartProvider.notifier).addToCart(
        id: 'menu_item_burger',
        name: 'Abaküs Burger',
        desc: '',
        price: 120,
        selectedModifiers: const [
          SelectedModifier(
            groupId: 'sauce',
            groupName: 'Sos',
            optionId: 'extra_sos',
            optionName: 'Ekstra Sos',
            extraPrice: 10,
          ),
        ],
      );
      await tester.pumpAndSettle();

      expect(find.byType(BowlCanvas), findsNothing);
      // Modifier ozeti hala eskisi gibi metin olarak gorunur.
      expect(find.text('Ekstra Sos'), findsOneWidget);
    },
  );

  testWidgets(
    'sepette hem custom bowl hem normal urun varken sadece bowl satirinda onizleme cikar',
    (tester) async {
      final container = await pumpCart(tester);

      container.read(cartProvider.notifier)
        ..addToCart(
          id: 'custom_bowl_456',
          name: 'Kendi Bowlun',
          desc: '',
          price: 0,
          selectedModifiers: const [
            SelectedModifier(
              groupId: 'salads',
              groupName: 'Salatalar',
              optionId: 'bb_salad_mevsim',
              optionName: 'Mevsim Salata',
              extraPrice: 15,
            ),
          ],
        )
        ..addToCart(
          id: 'menu_item_wrap',
          name: 'Tavuk Wrap',
          desc: '',
          price: 90,
        );
      await tester.pumpAndSettle();

      expect(find.byType(BowlCanvas), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
