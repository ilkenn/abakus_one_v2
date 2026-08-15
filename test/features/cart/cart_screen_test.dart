import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:abakus_one_v2/features/bowl_builder/presentation/widgets/bowl_canvas.dart';
import 'package:abakus_one_v2/features/cart/presentation/providers/cart_provider.dart';
import 'package:abakus_one_v2/features/cart/presentation/providers/shopping_channel_provider.dart';
import 'package:abakus_one_v2/features/cart/presentation/screens/cart_screen.dart';
import 'package:abakus_one_v2/features/cart/presentation/screens/checkout_screen.dart';
import 'package:abakus_one_v2/features/cart/presentation/screens/takeaway_checkout_screen.dart';
import 'package:abakus_one_v2/features/cart/presentation/screens/takeaway_guest_checkout_screen.dart';
import 'package:abakus_one_v2/features/menu/domain/models/selected_modifier.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/features/takeaway/domain/models/takeaway_guest_context.dart';
import 'package:abakus_one_v2/features/takeaway/presentation/providers/takeaway_guest_dependencies_provider.dart';

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

  group('Faz D.4 — Siparişi Tamamla dispatch, takeaway guest branch', () {
    setUp(() {
      // TakeawayGuestCheckoutScreen resolves a pending-submission-key via
      // shared_preferences in initState — unmocked, the platform channel
      // never responds under `flutter test`, hanging pumpAndSettle.
      SharedPreferences.setMockInitialValues({});
    });

    Future<ProviderContainer> pumpCartWithItem(WidgetTester tester) async {
      tester.view.physicalSize = const Size(480, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: CartScreen()),
        ),
      );
      container.read(cartProvider.notifier).addToCart(
            id: 'p1',
            name: 'Falafel Bowl',
            desc: '',
            price: 120,
            pricedForChannel: OrderChannel.takeaway,
          );
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets(
        'aktif bir takeaway GUEST oturumu varken Siparişi Tamamla, '
        'TakeawayGuestCheckoutScreen açar (TakeawayCheckoutScreen/'
        'CheckoutScreen değil)', (tester) async {
      final container = await pumpCartWithItem(tester);
      container.read(shoppingChannelProvider.notifier).selectTakeaway(
            restaurantId: 'restaurant-1',
            branchId: 'branch-1',
            branchDisplayName: 'Abaküs Ortaköy',
          );
      container.read(takeawayGuestContextProvider.notifier).set(
            TakeawayGuestContext(
              sessionId: 'tags-1',
              organizationId: 'org-1',
              restaurantId: 'restaurant-1',
              branchId: 'branch-1',
              branchDisplayName: 'Abaküs Ortaköy',
              expiresAt: DateTime.now().add(const Duration(minutes: 30)),
              guestAuthUid: 'anon-uid-1',
            ),
          );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Siparişi Tamamla'));
      await tester.pumpAndSettle();

      expect(find.byType(TakeawayGuestCheckoutScreen), findsOneWidget);
      expect(find.byType(TakeawayCheckoutScreen), findsNothing);
      expect(find.byType(CheckoutScreen), findsNothing);
    });

    testWidgets(
        'takeaway kanalı seçili ama guest oturumu YOK (authenticated Faz '
        'C akışı) — mevcut davranış korunur: TakeawayCheckoutScreen açılır',
        (tester) async {
      final container = await pumpCartWithItem(tester);
      container.read(shoppingChannelProvider.notifier).selectTakeaway(
            restaurantId: 'restaurant-1',
            branchId: 'branch-1',
            branchDisplayName: 'Abaküs Ortaköy',
          );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Siparişi Tamamla'));
      await tester.pumpAndSettle();

      expect(find.byType(TakeawayCheckoutScreen), findsOneWidget);
      expect(find.byType(TakeawayGuestCheckoutScreen), findsNothing);
    });
  });
}
