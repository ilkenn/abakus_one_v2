import 'package:abakus_one_v2/core/layout/app_breakpoints.dart';
import 'package:abakus_one_v2/core/utils/clock_provider.dart';
import 'package:abakus_one_v2/features/pos/data/pos_order_repository.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/pos_dependencies_provider.dart';
import 'package:abakus_one_v2/features/pos/presentation/screens/pos_cashier_screen.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/exchange_rate_provider.dart';
import 'package:abakus_one_v2/shared/models/exchange_rate_snapshot.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_clock.dart';

class _FakeExchangeRateProvider implements ExchangeRateProvider {
  _FakeExchangeRateProvider(this._rates);

  final Map<String, ExchangeRateSnapshot> _rates;

  @override
  Future<ExchangeRateSnapshot> getTodayRate(Currency currency) async {
    final rate = _rates[currency.isoCode];
    if (rate == null) throw StateError('no rate for ${currency.isoCode}');
    return rate;
  }

  @override
  Future<ExchangeRateSnapshot> getRateAt(Currency currency, DateTime at) =>
      getTodayRate(currency);

  @override
  Future<void> refreshRates() async {}
}

void main() {
  late InMemoryPosOrderRepository repository;

  Future<void> pumpCashier(
    WidgetTester tester, {
    Size viewportSize = const Size(400, 900),
    ExchangeRateProvider? exchangeRateProvider,
  }) async {
    tester.view.physicalSize = viewportSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    repository = InMemoryPosOrderRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clockProvider.overrideWithValue(FakeClock(DateTime(2026, 7, 29, 12, 0))),
          posOrderRepositoryProvider.overrideWithValue(repository),
          if (exchangeRateProvider != null)
            exchangeRateProviderProvider.overrideWithValue(exchangeRateProvider),
        ],
        child: const MaterialApp(
          home: PosCashierScreen(
            sessionId: 'session-1',
            branchId: 'branch-1',
            openedByStaffId: 'staff-1',
            restaurantId: 'restaurant-abakus',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The first product tile in a single-column phone-width grid can be
  /// taller than the visible viewport, so its label needs to be scrolled
  /// into view within the grid before `tap` can hit it reliably.
  Future<void> tapProduct(WidgetTester tester, String name) async {
    final finder = find.text(name).first;
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  group('PosCashierScreen — layout', () {
    testWidgets('phone width stacks the product and order panels vertically', (
      tester,
    ) async {
      await pumpCashier(tester, viewportSize: const Size(400, 900));

      expect(find.text('Ürünler'), findsOneWidget);
      expect(find.text('Mevcut Sipariş'), findsOneWidget);
      expect(find.byType(VerticalDivider), findsNothing);

      final productsTop = tester.getTopLeft(find.text('Ürünler'));
      final orderTop = tester.getTopLeft(find.text('Mevcut Sipariş'));
      expect(orderTop.dy, greaterThan(productsTop.dy));
    });

    testWidgets('desktop width places the product and order panels side by side', (
      tester,
    ) async {
      await pumpCashier(
        tester,
        viewportSize: const Size(AppBreakpoints.desktop + 200, 900),
      );

      expect(find.byType(VerticalDivider), findsOneWidget);

      final productsTop = tester.getTopLeft(find.text('Ürünler'));
      final orderTop = tester.getTopLeft(find.text('Mevcut Sipariş'));
      expect(orderTop.dx, greaterThan(productsTop.dx));
    });
  });

  group('PosCashierScreen — basic cashier flow', () {
    testWidgets(
      'starts a session, adds a product, and shows it in the order panel',
      (tester) async {
        await pumpCashier(tester);

        expect(find.text('Siparişe henüz ürün eklenmedi'), findsOneWidget);

        await tapProduct(tester, 'Mexifit Bowl');

        expect(find.text('Siparişe henüz ürün eklenmedi'), findsNothing);
        expect(find.text('Mexifit Bowl'), findsWidgets);
        expect(repository.draftIds, contains('session-1'));
      },
    );

    testWidgets('submitting an order opens the payment screen for the new order', (
      tester,
    ) async {
      await pumpCashier(tester);

      await tapProduct(tester, 'Mexifit Bowl');

      await tester.tap(find.widgetWithText(ElevatedButton, 'Siparişi Gönder'));
      await tester.pumpAndSettle();

      expect(find.text('Ödeme'), findsOneWidget);
      expect(find.text('Ödeme Yöntemi'), findsOneWidget);
      expect(repository.submittedOrders, hasLength(1));
      expect(repository.draftIds, isEmpty);
    });

    testWidgets('navigating back from the payment screen shows the confirmation view', (
      tester,
    ) async {
      await pumpCashier(tester);

      await tapProduct(tester, 'Mexifit Bowl');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Siparişi Gönder'));
      await tester.pumpAndSettle();

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.text('Sipariş oluşturuldu'), findsOneWidget);
      expect(find.text('Yeni Sipariş Başlat'), findsOneWidget);
    });

    testWidgets(
      'the submit button is disabled while the order has no lines',
      (tester) async {
        await pumpCashier(tester);

        final button = tester.widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'Siparişi Gönder'),
        );
        expect(button.onPressed, isNull);
      },
    );
  });

  group('PosCashierScreen — currency presentation', () {
    testWidgets(
      'shows an "unavailable" label when no exchange rate exists (default provider)',
      (tester) async {
        await pumpCashier(tester);

        await tapProduct(tester, 'Mexifit Bowl');

        expect(find.text('Döviz kuru şu anda kullanılamıyor'), findsOneWidget);
      },
    );

    testWidgets('shows approximate EUR/USD totals when rates are available', (
      tester,
    ) async {
      final timestamp = DateTime(2026, 7, 29);
      await pumpCashier(
        tester,
        exchangeRateProvider: _FakeExchangeRateProvider({
          'EUR': ExchangeRateSnapshot.capture(
            sourceCurrency: Currency.eur,
            marketSellingRate: Money.fromWhole(47, Currency.tryLira),
            rateTimestamp: timestamp,
            rateSource: 'manual',
          ),
          'USD': ExchangeRateSnapshot.capture(
            sourceCurrency: Currency.usd,
            marketSellingRate: Money.fromWhole(41, Currency.tryLira),
            rateTimestamp: timestamp,
            rateSource: 'manual',
          ),
        }),
      );

      await tapProduct(tester, 'Mexifit Bowl');

      expect(find.textContaining('Yaklaşık EUR'), findsOneWidget);
      expect(find.textContaining('Yaklaşık USD'), findsOneWidget);
      expect(find.text('Döviz kuru şu anda kullanılamıyor'), findsNothing);
    });

    testWidgets('submission remains allowed when exchange rates are unavailable', (
      tester,
    ) async {
      await pumpCashier(tester);

      await tapProduct(tester, 'Mexifit Bowl');

      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Siparişi Gönder'),
      );
      expect(button.onPressed, isNotNull);
    });
  });

  group('PosCashierScreen — quick product discount', () {
    testWidgets('preset buttons are disabled until a line is selected', (
      tester,
    ) async {
      await pumpCashier(tester);
      await tapProduct(tester, 'Mexifit Bowl');

      expect(
        find.text('Hızlı indirim uygulamak için önce bir ürün seçin'),
        findsOneWidget,
      );
      final preset = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, '%10'),
      );
      expect(preset.onPressed, isNull);
    });

    testWidgets('selecting a line enables the presets and applying one shows the discount', (
      tester,
    ) async {
      await pumpCashier(tester);
      await tapProduct(tester, 'Mexifit Bowl');

      // The cart line tile (not the product-grid tile) is the InkWell
      // ancestor of its quantity-decrement icon — a distinguishing marker
      // since "Mexifit Bowl" text now also appears in the product grid.
      final cartLineInkWell = find.ancestor(
        of: find.byIcon(Icons.remove_circle_outline),
        matching: find.byType(InkWell),
      );
      await tester.tap(cartLineInkWell.first);
      await tester.pumpAndSettle();

      expect(
        find.text('Hızlı indirim (seçili ürüne uygulanır)'),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(OutlinedButton, '%10'));
      await tester.pumpAndSettle();

      expect(find.textContaining('%10 indirim'), findsOneWidget);
      expect(find.text('İndirimi Kaldır'), findsOneWidget);
    });
  });
}
