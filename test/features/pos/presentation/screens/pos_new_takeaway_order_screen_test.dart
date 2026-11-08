import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/features/menu/domain/models/menu_product.dart';
import 'package:abakus_one_v2/features/menu/presentation/providers/menu_catalog_provider.dart';
import 'package:abakus_one_v2/features/pos/data/pos_action_gateway.dart';
import 'package:abakus_one_v2/features/pos/presentation/screens/pos_new_takeaway_order_screen.dart';
import 'package:abakus_one_v2/features/takeaway/data/submit_takeaway_order_gateway.dart';
import 'package:abakus_one_v2/features/takeaway/presentation/providers/takeaway_dependencies_provider.dart';

class _FakeSubmitTakeawayOrderGateway implements SubmitTakeawayOrderGateway {
  int staffEntryCallCount = 0;
  List<TakeawayOrderItem>? lastItems;
  String? lastContactFirstName;
  String? lastContactPhone;
  Object? throwOnStaffEntry;

  @override
  Future<SubmitTakeawayOrderResult> submitStaffEntryOrder({
    required String submissionKey,
    required String organizationId,
    required String branchId,
    required String deviceId,
    required String deviceSessionId,
    required List<TakeawayOrderItem> items,
    required String contactFirstName,
    required String contactLastName,
    required String contactPhone,
  }) async {
    if (throwOnStaffEntry != null) throw throwOnStaffEntry!;
    staffEntryCallCount += 1;
    lastItems = items;
    lastContactFirstName = contactFirstName;
    lastContactPhone = contactPhone;
    return const SubmitTakeawayOrderResult(
        orderId: 'order-1', orderNumber: 'TA-001', duplicate: false);
  }

  @override
  Future<SubmitTakeawayOrderResult> submitAuthenticatedOrder({
    required String submissionKey,
    required String restaurantId,
    required String branchId,
    required DateTime pickupTime,
    required List<TakeawayOrderItem> items,
    required String contactFirstName,
    required String contactLastName,
    required String contactPhone,
    int requestedBoncukAmount = 0,
    String? selectedRewardId,
    String? selectedCampaignId,
  }) {
    throw UnimplementedError('not exercised by this screen');
  }

  @override
  Future<SubmitTakeawayOrderResult> submitGuestOrder({
    required String submissionKey,
    required String takeawaySessionId,
    required List<TakeawayOrderItem> items,
    required String contactFirstName,
    required String contactLastName,
    required String contactPhone,
  }) {
    throw UnimplementedError('not exercised by this screen');
  }
}

const _ctx = PosDeviceContext(
  organizationId: 'org-1',
  branchId: 'branch-1',
  deviceId: 'device-1',
  deviceSessionId: 'session-1',
);

const _simpleProduct = MenuProduct(
  id: 'prod_test_1',
  categoryId: 'cat_test',
  name: 'Paket Kutu',
  description: '',
  basePrice: 100,
  imageKey: 'placeholder',
);

Future<_FakeSubmitTakeawayOrderGateway> _pump(
  WidgetTester tester, {
  List<MenuProduct> products = const [_simpleProduct],
}) async {
  final gateway = _FakeSubmitTakeawayOrderGateway();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        submitTakeawayOrderGatewayProvider.overrideWithValue(gateway),
        menuProductsProvider.overrideWithValue(products),
      ],
      child: const MaterialApp(
        home: PosNewTakeawayOrderScreen(ctx: _ctx),
      ),
    ),
  );
  await tester.pump();
  return gateway;
}

void main() {
  testWidgets(
      'ad/soyad/telefon ve en az bir urun olmadan Siparisi Olustur hicbir '
      'sey gondermez, hata gosterir', (tester) async {
    final gateway = await _pump(tester);

    await tester.tap(find.byKey(const Key('submitNewTakeawayOrderButton')));
    await tester.pump();

    expect(gateway.staffEntryCallCount, 0);
    expect(find.textContaining('zorunludur'), findsOneWidget);
  });

  testWidgets(
      'urun secip ad/soyad/telefon girilince Siparisi Olustur '
      'submitStaffEntryOrder cagirir ve basariyla kapanir', (tester) async {
    final gateway = await _pump(tester);

    await tester.enterText(
        find.byKey(const Key('takeawayFirstNameField')), 'Ahmet');
    await tester.enterText(
        find.byKey(const Key('takeawayLastNameField')), 'Yılmaz');
    await tester.enterText(
        find.byKey(const Key('takeawayPhoneField')), '+905551112233');

    await tester.tap(find.byKey(const Key('takeawayProduct_prod_test_1')));
    await tester.pump();

    expect(find.text('Paket Kutu'), findsWidgets);

    await tester.tap(find.byKey(const Key('submitNewTakeawayOrderButton')));
    await tester.pumpAndSettle();

    expect(gateway.staffEntryCallCount, 1);
    expect(gateway.lastContactFirstName, 'Ahmet');
    expect(gateway.lastContactPhone, '+905551112233');
    expect(gateway.lastItems, hasLength(1));
  });

  testWidgets('gateway hata firlatinca sepet/alanlar korunur, hata gosterilir',
      (tester) async {
    final gateway = await _pump(tester);
    gateway.throwOnStaffEntry =
        const SubmitTakeawayOrderException('internal', 'Sunucu hatası.');

    await tester.enterText(
        find.byKey(const Key('takeawayFirstNameField')), 'Ahmet');
    await tester.enterText(
        find.byKey(const Key('takeawayLastNameField')), 'Yılmaz');
    await tester.enterText(
        find.byKey(const Key('takeawayPhoneField')), '+905551112233');
    await tester.tap(find.byKey(const Key('takeawayProduct_prod_test_1')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('submitNewTakeawayOrderButton')));
    await tester.pumpAndSettle();

    expect(find.text('Sunucu hatası.'), findsOneWidget);
    expect(find.text('Paket Kutu'), findsWidgets,
        reason: 'sepet korunmali, hata sonrasi kaybolmamali');
  });
}
