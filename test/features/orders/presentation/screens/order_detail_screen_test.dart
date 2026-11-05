import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/orders/data/cancel_dine_in_order_gateway.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_model.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_status.dart';
import 'package:abakus_one_v2/features/orders/presentation/providers/cancel_dine_in_order_dependencies_provider.dart';
import 'package:abakus_one_v2/features/orders/presentation/screens/order_detail_screen.dart';

/// Self-Order QR Faz 4 — records calls, never touches the real Firebase
/// SDK.
class _FakeCancelDineInOrderGateway implements CancelDineInOrderGateway {
  int callCount = 0;
  String? lastOrderId;
  CancelDineInOrderException? errorToThrow;

  @override
  Future<CancelDineInOrderResult> cancel({required String orderId}) async {
    callCount += 1;
    lastOrderId = orderId;
    final error = errorToThrow;
    if (error != null) throw error;
    return CancelDineInOrderResult(
      orderId: orderId,
      status: 'cancelled',
      duplicate: false,
    );
  }
}

/// Server-Authoritative Campaign Engine P8-C (2026-08-25) — proves
/// `OrderDetailScreen` reconstructs a HISTORICAL campaign redemption
/// entirely from `OrderModel.campaignTitle`/`campaignDiscountMinorUnits`
/// (themselves frozen from the canonical `Order.campaign` snapshot at read
/// time, never a live campaign re-lookup — see `OrderModel
/// .fromCanonicalOrder`'s own doc comment).
///
/// No `ordersProvider`/auth override is needed: with no signed-in session
/// (the default in a bare `ProviderScope`), `OrdersNotifier.build()`
/// resolves to an empty list without touching Firebase, and the screen's
/// own `.valueOrNull ?? [widget.order]` / `firstWhere(..., orElse: () =>
/// widget.order)` fallback renders the [OrderModel] passed in directly —
/// exactly the same pattern this screen already documents for "still
/// loading" display.
OrderModel _order({
  String? campaignTitle,
  int? campaignDiscountMinorUnits,
  String? catalogRewardTitle,
  int? catalogRewardCoveredValueMinorUnits,
  int? boncukRedemptionBoncukUsed,
  int? boncukRedemptionValueMinorUnits,
  OrderChannel channel = OrderChannel.takeaway,
  OrderStatus lifecycleStatus = OrderStatus.preparing,
  String status = 'Hazırlanıyor',
}) {
  return OrderModel(
    id: 'order-1',
    date: '25.08.2026',
    totalAmount: 225.0,
    status: status,
    channel: channel,
    lifecycleStatus: lifecycleStatus,
    campaignTitle: campaignTitle,
    campaignDiscountMinorUnits: campaignDiscountMinorUnits,
    catalogRewardTitle: catalogRewardTitle,
    catalogRewardCoveredValueMinorUnits: catalogRewardCoveredValueMinorUnits,
    boncukRedemptionBoncukUsed: boncukRedemptionBoncukUsed,
    boncukRedemptionValueMinorUnits: boncukRedemptionValueMinorUnits,
  );
}

void main() {
  testWidgets(
      'a campaign redemption is reconstructed from the order snapshot and '
      'shown in the detail screen', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: OrderDetailScreen(
            order: _order(
              campaignTitle: 'Yaz İndirimi',
              campaignDiscountMinorUnits: 1500,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('orderDetailCampaignInfo')), findsOneWidget);
    expect(find.textContaining('Yaz İndirimi uygulandı'), findsOneWidget);
    expect(find.textContaining('İndirim: 15 TL'), findsOneWidget);
  });

  testWidgets('an order with no campaign shows no campaign info block',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: OrderDetailScreen(order: _order()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('orderDetailCampaignInfo')), findsNothing);
  });

  /// Customer-side closure audit fix — `OrderModel.fromCanonicalOrder`
  /// previously dropped `Order.catalogReward`/`Order.boncukRedemption`
  /// entirely (only `campaign` survived the projection), so a customer
  /// could not see past Boncuk/reward usage on a historical order even
  /// though the backend's immutable snapshot always carried it.
  testWidgets(
      'a catalog-reward redemption is reconstructed from the order snapshot '
      'and shown in the detail screen', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: OrderDetailScreen(
            order: _order(
              catalogRewardTitle: 'Ücretsiz İçecek',
              catalogRewardCoveredValueMinorUnits: 2000,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
        find.byKey(const Key('orderDetailCatalogRewardInfo')), findsOneWidget);
    expect(find.textContaining('Ücretsiz İçecek ödülü kullanıldı'),
        findsOneWidget);
  });

  testWidgets(
      'a cash Boncuk redemption is reconstructed from the order snapshot '
      'and shown in the detail screen', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: OrderDetailScreen(
            order: _order(
              boncukRedemptionBoncukUsed: 10,
              boncukRedemptionValueMinorUnits: 2000,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('orderDetailBoncukRedemptionInfo')),
        findsOneWidget);
    expect(find.textContaining('10 Boncuk kullanıldı'), findsOneWidget);
    expect(find.textContaining('Değer: 20 TL'), findsOneWidget);
  });

  testWidgets(
      'an order with no catalog reward or Boncuk redemption shows neither info block',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: OrderDetailScreen(order: _order()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('orderDetailCatalogRewardInfo')), findsNothing);
    expect(
        find.byKey(const Key('orderDetailBoncukRedemptionInfo')), findsNothing);
  });

  group('Self-Order QR Faz 4 — gercek dine-in musteri iptali', () {
    Future<_FakeCancelDineInOrderGateway> pumpDineInOrder(
      WidgetTester tester, {
      OrderStatus lifecycleStatus = OrderStatus.pendingConfirmation,
    }) async {
      final gateway = _FakeCancelDineInOrderGateway();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cancelDineInOrderGatewayProvider.overrideWithValue(gateway),
          ],
          child: MaterialApp(
            home: OrderDetailScreen(
              order: _order(
                channel: OrderChannel.dineInQr,
                lifecycleStatus: lifecycleStatus,
                status: 'Onay Bekliyor',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return gateway;
    }

    testWidgets(
        'pendingConfirmation durumundaki bir dineInQr siparisinde Iptal Et '
        'butonu gorunur', (tester) async {
      await pumpDineInOrder(tester);

      expect(find.text('Siparişi İptal Et'), findsOneWidget);
    });

    testWidgets(
        'confirmed durumuna gecmis bir dineInQr siparisinde Iptal Et '
        'butonu artik gorunmez — "mutfak/kasa onayina kadar" kurali',
        (tester) async {
      await pumpDineInOrder(tester, lifecycleStatus: OrderStatus.confirmed);

      expect(find.text('Siparişi İptal Et'), findsNothing);
    });

    testWidgets(
        'Iptal Et -> onay dialogunda Vazgec secilirse gateway hic '
        'cagrilmaz', (tester) async {
      final gateway = await pumpDineInOrder(tester);

      await tester.tap(find.text('Siparişi İptal Et'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();

      expect(gateway.callCount, 0);
    });

    testWidgets(
        'Iptal Et -> onay dialogunda onaylanirsa gercek gateway dogru '
        'orderId ile cagrilir ve basari mesaji gosterilir', (tester) async {
      final gateway = await pumpDineInOrder(tester);

      await tester.tap(find.text('Siparişi İptal Et'));
      await tester.pumpAndSettle();
      // Dialogdaki "Siparişi İptal Et" butonu (ikinci eslesme) — ilki
      // ekrandaki ana buton.
      await tester.tap(find.text('Siparişi İptal Et').last);
      await tester.pumpAndSettle();

      expect(gateway.callCount, 1);
      expect(gateway.lastOrderId, 'order-1');
      expect(
        find.text('Siparişiniz başarıyla iptal edilmiştir.'),
        findsOneWidget,
      );
    });

    testWidgets(
        'gateway failed-precondition ile reddederse ozel bir hata mesaji '
        'gosterilir, uygulama cokmez', (tester) async {
      final gateway = await pumpDineInOrder(tester);
      gateway.errorToThrow = const CancelDineInOrderException(
        'failed-precondition',
        'This order can no longer be cancelled by the customer.',
      );

      await tester.tap(find.text('Siparişi İptal Et'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Siparişi İptal Et').last);
      await tester.pumpAndSettle();

      expect(
        find.textContaining('artık müşteri tarafından iptal edilemez'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
