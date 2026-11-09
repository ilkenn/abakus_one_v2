import 'package:abakus_one_v2/features/cart/presentation/guards/cart_add_guard.dart';
import 'package:abakus_one_v2/features/cart/presentation/providers/cart_provider.dart';
import 'package:abakus_one_v2/features/menu/domain/models/menu_product.dart';
import 'package:abakus_one_v2/features/menu/presentation/providers/menu_catalog_provider.dart';
import 'package:abakus_one_v2/features/menu/presentation/screens/menu_screen.dart';
import 'package:abakus_one_v2/features/qr/domain/models/active_table_context.dart';
import 'package:abakus_one_v2/features/qr/domain/models/guest_session.dart';
import 'package:abakus_one_v2/features/qr/domain/models/table_session.dart';
import 'package:abakus_one_v2/features/qr/presentation/providers/active_table_context_provider.dart';
import 'package:abakus_one_v2/features/qr/presentation/providers/menu_showcase_mode_provider.dart';
import 'package:abakus_one_v2/features/qr/presentation/screens/menu_showcase_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _plainProduct = MenuProduct(
  id: 'test_plain_prod',
  categoryId: 'test_cat',
  name: 'Sade Test Ürün',
  description: 'Test açıklaması',
  basePrice: 30,
  imageKey: 'does-not-exist',
  allergens: ['gluten'],
);

ActiveTableContext _tableContext() {
  final now = DateTime(2026, 11, 9, 12);
  return ActiveTableContext(
    restaurantId: 'restaurant-1',
    branchId: 'branch-1',
    branchName: 'Abaküs',
    tableId: 'table-1',
    tableName: 'Masa 1',
    session: TableSession(
      id: 'tsess-1',
      restaurantId: 'restaurant-1',
      branchId: 'branch-1',
      tableId: 'table-1',
      status: TableSessionStatus.active,
      openedAt: now,
      guestSessionIds: const [],
      activeOrderIds: const [],
    ),
    guestSession: GuestSession(
      id: 'gsession-1',
      tableSessionId: 'tsess-1',
      branchId: 'branch-1',
      tableId: 'table-1',
      detectedLanguageCode: 'tr',
      selectedLanguageCode: 'tr',
      createdAt: now,
      lastSeenAt: now,
      status: GuestSessionStatus.active,
    ),
  );
}

void main() {
  group('isMenuShowcaseActiveProvider', () {
    test('off by default — the normal app is never restricted', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(isMenuShowcaseActiveProvider), isFalse);
    });

    test('on after entering the showcase menu', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(menuShowcaseModeProvider.notifier).enter();
      expect(container.read(isMenuShowcaseActiveProvider), isTrue);
    });

    test('a scanned table lifts the restriction even if the flag is still set',
        () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(menuShowcaseModeProvider.notifier).enter();
      container.read(activeTableContextProvider.notifier).set(_tableContext());
      expect(container.read(isMenuShowcaseActiveProvider), isFalse);
    });
  });

  group('MenuShowcaseScreen', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer(overrides: [
        menuProductsProvider.overrideWithValue([_plainProduct]),
      ]);
    });
    tearDown(() => container.dispose());

    Future<void> pump(WidgetTester tester, Widget home) async {
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: home),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets(
        'shows the real menu (products, prices) with the showcase banner',
        (tester) async {
      await pump(tester, const MenuShowcaseScreen());

      expect(find.byKey(const Key('menuShowcaseBanner')), findsOneWidget);
      expect(find.byType(MenuScreen), findsOneWidget);
      expect(find.text('Sade Test Ürün'), findsWidgets);
      expect(container.read(isMenuShowcaseActiveProvider), isTrue);
    });

    testWidgets(
        'add to cart opens the "scan your table QR" modal and adds nothing',
        (tester) async {
      await pump(tester, const MenuShowcaseScreen());

      final addButton = find.byTooltip('Sepete ekle');
      await tester.ensureVisible(addButton);
      await tester.pumpAndSettle();
      await tester.tap(addButton);
      await tester.pumpAndSettle();

      expect(find.text(ShowcaseOrderingBlockedDialog.message), findsOneWidget);
      expect(container.read(cartProvider), isEmpty);

      await tester.tap(find.text('Tamam'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('outside the showcase the same button still adds to the cart',
        (tester) async {
      await pump(tester, const MenuScreen());

      final addButton = find.byTooltip('Sepete ekle');
      await tester.ensureVisible(addButton);
      await tester.pumpAndSettle();
      await tester.tap(addButton);
      await tester.pumpAndSettle();

      expect(container.read(cartProvider), hasLength(1));
      expect(find.text(ShowcaseOrderingBlockedDialog.message), findsNothing);
    });
  });
}
