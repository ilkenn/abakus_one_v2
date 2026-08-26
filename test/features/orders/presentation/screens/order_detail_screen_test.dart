import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_model.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_status.dart';
import 'package:abakus_one_v2/features/orders/presentation/screens/order_detail_screen.dart';

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
}) {
  return OrderModel(
    id: 'order-1',
    date: '25.08.2026',
    totalAmount: 225.0,
    status: 'Hazırlanıyor',
    channel: OrderChannel.takeaway,
    lifecycleStatus: OrderStatus.preparing,
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
}
