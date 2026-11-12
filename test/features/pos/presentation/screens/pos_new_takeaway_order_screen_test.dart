import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/features/courier/domain/identity/courier.dart';
import 'package:abakus_one_v2/features/courier/domain/identity/courier_registry_status.dart';
import 'package:abakus_one_v2/features/menu/domain/models/menu_product.dart';
import 'package:abakus_one_v2/features/menu/domain/models/sale_unit.dart';
import 'package:abakus_one_v2/features/menu/presentation/providers/menu_catalog_provider.dart';
import 'package:abakus_one_v2/features/orders/data/canonical_order_repository.dart';
import 'package:abakus_one_v2/features/orders/presentation/providers/orders_provider.dart';
import 'package:abakus_one_v2/features/pos/data/pos_action_gateway.dart';
import 'package:abakus_one_v2/features/pos/data/pos_phone_order_gateway.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/courier_dispatch_dependencies_provider.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/pos_workspace_providers.dart';
import 'package:abakus_one_v2/features/pos/presentation/screens/pos_new_takeaway_order_screen.dart';

class _FakePhoneOrderGateway implements PosPhoneOrderGateway {
  int takeawayCalls = 0;
  int deliveryCalls = 0;
  PosPhoneOrderContact? lastContact;
  PosDeliveryAddressInput? lastAddress;
  List<Map<String, dynamic>>? lastItems;
  String? lastKitchenNote;
  String? lastCourierNote;
  String? lastPaymentMethodId;
  int? lastDeliveryFee;
  String? lastPlannedCourierId;
  PosPhoneOrderException? error;
  List<PosCustomerBookEntry> searchResults = const [];
  String? lastQuery;

  @override
  Future<PosPhoneOrderResult> submitTakeaway({
    required PosDeviceContext ctx,
    required String submissionKey,
    required PosPhoneOrderContact contact,
    required List<Map<String, dynamic>> items,
    required String kitchenNote,
  }) async {
    final e = error;
    if (e != null) throw e;
    takeawayCalls += 1;
    lastContact = contact;
    lastItems = items;
    lastKitchenNote = kitchenNote;
    return const PosPhoneOrderResult(
        orderId: 'order-1', orderNumber: 'TA-1', duplicate: false);
  }

  @override
  Future<PosPhoneOrderResult> submitDelivery({
    required PosDeviceContext ctx,
    required String submissionKey,
    required PosPhoneOrderContact contact,
    required PosDeliveryAddressInput address,
    required List<Map<String, dynamic>> items,
    required String courierNote,
    required String kitchenNote,
    required String paymentMethodId,
    required int deliveryFeeMinorUnits,
    String? plannedCourierId,
  }) async {
    final e = error;
    if (e != null) throw e;
    deliveryCalls += 1;
    lastContact = contact;
    lastAddress = address;
    lastItems = items;
    lastCourierNote = courierNote;
    lastKitchenNote = kitchenNote;
    lastPaymentMethodId = paymentMethodId;
    lastDeliveryFee = deliveryFeeMinorUnits;
    lastPlannedCourierId = plannedCourierId;
    return const PosPhoneOrderResult(
        orderId: 'order-2', orderNumber: 'DL-ABCD1234', duplicate: false);
  }

  @override
  Future<List<PosCustomerBookEntry>> searchCustomers({
    required String organizationId,
    required String query,
  }) async {
    lastQuery = query;
    return searchResults;
  }
}

const _ctx = PosDeviceContext(
  organizationId: 'org-1',
  branchId: 'branch-1',
  deviceId: 'device-1',
  deviceSessionId: 'session-1',
);

const _box = MenuProduct(
  id: 'prod_test_1',
  categoryId: 'cat_test',
  name: 'Paket Kutu',
  description: '',
  basePrice: 450,
  imageKey: 'placeholder',
);

const _weighed = MenuProduct(
  id: 'prod_kg',
  categoryId: 'cat_test',
  name: 'Tartılı Salata',
  description: '',
  basePrice: 400,
  imageKey: 'placeholder',
  saleUnit: SaleUnit.kilogram,
);

final _couriers = [
  Courier(
    id: 'courier-1',
    primaryBranchId: 'branch-1',
    displayName: 'Ahmet',
    phoneNumber: '+905550000001',
    registeredAt: DateTime(2026),
  ),
  Courier(
    id: 'courier-2',
    primaryBranchId: 'branch-1',
    displayName: 'Mehmet',
    phoneNumber: '+905550000002',
    registeredAt: DateTime(2026),
  ),
  Courier(
    id: 'courier-3',
    primaryBranchId: 'branch-1',
    displayName: 'Arşivli',
    phoneNumber: '+905550000003',
    registeredAt: DateTime(2026),
    status: CourierRegistryStatus.archived,
  ),
];

Future<_FakePhoneOrderGateway> _pump(
  WidgetTester tester, {
  PosPhoneOrderMode mode = PosPhoneOrderMode.takeaway,
}) async {
  await tester.binding.setSurfaceSize(const Size(1400, 2200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final gateway = _FakePhoneOrderGateway();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        posPhoneOrderGatewayProvider.overrideWithValue(gateway),
        menuProductsProvider.overrideWithValue(const [_box, _weighed]),
        topSellingProductsProvider.overrideWith((ref, ctx) async => const []),
        allCouriersForBranchProvider
            .overrideWith((ref, branchId) => Stream.value(_couriers)),
        canonicalOrderRepositoryProvider
            .overrideWithValue(InMemoryCanonicalOrderRepository()),
      ],
      child: MaterialApp(
        home: PosNewTakeawayOrderScreen(ctx: _ctx, initialMode: mode),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return gateway;
}

Future<void> _addProduct(WidgetTester tester,
    [String name = 'Paket Kutu']) async {
  await tester.enterText(find.byKey(const Key('productSearchField')), name);
  await tester.pump();
  await tester.tap(find.descendant(
    of: find.byType(GridView),
    matching: find.text(name),
  ));
  await tester.pumpAndSettle();
}

Future<void> _fillContact(WidgetTester tester,
    {String phone = '0532 111 22 33'}) async {
  await tester.enterText(
      find.byKey(const Key('takeawayFirstNameField')), 'Ahmet');
  await tester.enterText(
      find.byKey(const Key('takeawayLastNameField')), 'Yılmaz');
  await tester.enterText(find.byKey(const Key('takeawayPhoneField')), phone);
}

Future<void> _fillAddress(WidgetTester tester) async {
  await tester.enterText(
      find.byKey(const Key('deliveryNeighborhoodField')), 'Caferağa');
  await tester.enterText(
      find.byKey(const Key('deliveryStreetField')), 'Moda Caddesi');
}

String _total(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('phoneOrderTotal'))).data!;

Future<void> _submit(WidgetTester tester) async {
  final button = find.byKey(const Key('submitNewTakeawayOrderButton'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> _tapChip(WidgetTester tester, String label) async {
  final chip = find.widgetWithText(ChoiceChip, label);
  await tester.ensureVisible(chip);
  await tester.pumpAndSettle();
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

Future<void> _search(WidgetTester tester, String query) async {
  await tester.enterText(find.byKey(const Key('customerSearchField')), query);
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await tester.pumpAndSettle();
}

void main() {
  group('Gel-Al', () {
    testWidgets('eksik musteri bilgisi ya da gecersiz telefon gonderilmez',
        (tester) async {
      final gateway = await _pump(tester);

      await _submit(tester);
      expect(gateway.takeawayCalls, 0);
      expect(find.textContaining('zorunludur'), findsOneWidget);

      await _fillContact(tester, phone: '12345');
      await _addProduct(tester);
      await _submit(tester);
      expect(gateway.takeawayCalls, 0);
      expect(find.textContaining('Telefon numarası geçerli değil'),
          findsOneWidget);
    });

    testWidgets(
        'Gel-Al fiyatlari +20 TL; siparis mutfak notuyla ve E.164 telefonla '
        'gonderilir', (tester) async {
      final gateway = await _pump(tester);
      await _fillContact(tester);
      await _addProduct(tester);
      await _addProduct(tester);

      expect(_total(tester), '940 TL', reason: '(450 + 20) × 2');
      await tester.enterText(
          find.byKey(const Key('kitchenNoteField')), 'Et orta-iyi pişsin');
      await _submit(tester);

      expect(gateway.takeawayCalls, 1);
      expect(gateway.lastContact!.phone, '+905321112233');
      expect(gateway.lastKitchenNote, 'Et orta-iyi pişsin');
      expect(gateway.lastItems!.single['quantity'], 2);
      expect(gateway.lastItems!.single['productId'], 'prod_test_1');
    });

    testWidgets('sunucu hatasinda sepet korunur, Turkce mesaj gosterilir',
        (tester) async {
      final gateway = await _pump(tester);
      gateway.error =
          const PosPhoneOrderException('internal', 'Internal error');
      await _fillContact(tester);
      await _addProduct(tester);

      await _submit(tester);

      expect(find.text('Sipariş gönderilemedi. Lütfen tekrar deneyin.'),
          findsOneWidget);
      expect(_total(tester), '470 TL');
    });

    testWidgets('tartili urun sepete eklenmez ve nedeni soylenir',
        (tester) async {
      await _pump(tester);
      await _addProduct(tester, 'Tartılı Salata');

      expect(find.text('Tartılı ürünler şimdilik yalnızca masada satılabilir.'),
          findsOneWidget);
      expect(_total(tester), '0 TL');
    });

    testWidgets('Gel-Al modunda paket servis alanlari gizlidir',
        (tester) async {
      await _pump(tester);

      expect(find.byKey(const Key('deliveryNeighborhoodField')), findsNothing);
      expect(find.byKey(const Key('courierNoteField')), findsNothing);
      expect(find.byKey(const Key('deliveryFeeField')), findsNothing);
      expect(find.byKey(const Key('printCourierSlipButton')), findsNothing);
      expect(find.byKey(const Key('kitchenNoteField')), findsOneWidget);
    });
  });

  group('Paket Servis', () {
    testWidgets(
        'paket fiyatlari ×1.35 / 5 TL yuvarlama; mod degisince sepet yeniden '
        'fiyatlanir', (tester) async {
      await _pump(tester);
      await _addProduct(tester);
      expect(_total(tester), '470 TL');

      await tester.tap(find.text('Paket Servis'));
      await tester.pumpAndSettle();

      expect(_total(tester), '610 TL', reason: '450 × 1.35 = 607.5 → 610');
    });

    testWidgets(
        'adres, kurye notu, yemek karti markasi, ucret ve planlanan kurye '
        'gonderilir; onaydan sonra fis yeniden yazdirilabilir', (tester) async {
      final gateway = await _pump(tester, mode: PosPhoneOrderMode.delivery);
      await _fillContact(tester);
      await _fillAddress(tester);
      await tester.enterText(
          find.byKey(const Key('courierNoteField')), 'Zile basmayın');
      await _addProduct(tester);
      await _tapChip(tester, 'Kapıda Yemek Kartı');
      expect(find.byKey(const Key('mealCardBrands')), findsOneWidget);
      await _tapChip(tester, 'Multinet');
      await tester.enterText(find.byKey(const Key('deliveryFeeField')), '30');
      await tester.pump();
      expect(_total(tester), '640 TL', reason: '610 + 30 TL fee');
      expect(find.widgetWithText(ChoiceChip, 'Arşivli'), findsNothing);
      await _tapChip(tester, 'Mehmet');

      await _submit(tester);

      expect(gateway.deliveryCalls, 1);
      expect(gateway.lastAddress!.neighborhoodName, 'Caferağa');
      expect(gateway.lastAddress!.streetName, 'Moda Caddesi');
      expect(gateway.lastCourierNote, 'Zile basmayın');
      expect(gateway.lastPaymentMethodId, 'multinet');
      expect(gateway.lastDeliveryFee, 3000);
      expect(gateway.lastPlannedCourierId, 'courier-2');
      expect(find.text('Paket Siparişi Onaylandı'), findsOneWidget);
      expect(find.byKey(const Key('reprintCourierSlipButton')), findsOneWidget);
    });

    testWidgets('mahalle / sokak olmadan paket siparisi gonderilmez',
        (tester) async {
      final gateway = await _pump(tester, mode: PosPhoneOrderMode.delivery);
      await _fillContact(tester);
      await _addProduct(tester);

      await _submit(tester);

      expect(gateway.deliveryCalls, 0);
      expect(find.textContaining('mahalle ve cadde / sokak zorunludur'),
          findsOneWidget);
    });

    testWidgets('kapida POS dogru odeme yontemine eslenir; ucret varsayilan 0',
        (tester) async {
      final gateway = await _pump(tester, mode: PosPhoneOrderMode.delivery);
      await _fillContact(tester);
      await _fillAddress(tester);
      await _addProduct(tester);
      await _tapChip(tester, 'Kapıda POS');

      await _submit(tester);

      expect(gateway.lastPaymentMethodId, 'credit_card');
      expect(gateway.lastDeliveryFee, 0);
    });
  });

  group('Müşteri Ara', () {
    testWidgets(
        'defterdeki musteri secilince tam telefon ve onceki adresler dolar',
        (tester) async {
      final gateway = await _pump(tester, mode: PosPhoneOrderMode.delivery);
      gateway.searchResults = const [
        PosCustomerBookEntry(
          isFromBook: true,
          id: 'org-1_hash',
          displayName: 'Ayşe Demir',
          firstName: 'Ayşe',
          lastName: 'Demir',
          phoneNumber: '+905321112233',
          phoneMasked: '***********33',
          addresses: [
            PosDeliveryAddressInput(
                neighborhoodName: 'Moda', streetName: 'Bahariye Caddesi'),
            PosDeliveryAddressInput(
                neighborhoodName: 'Caferağa', streetName: 'Moda Caddesi'),
          ],
          linkedCustomerId: null,
        ),
      ];

      await _search(tester, 'ayşe');
      expect(gateway.lastQuery, 'ayşe');
      expect(find.text('Defter'), findsOneWidget);
      await tester.tap(find.text('Ayşe Demir'));
      await tester.pumpAndSettle();

      String text(String key) =>
          tester.widget<TextField>(find.byKey(Key(key))).controller!.text;
      expect(text('takeawayFirstNameField'), 'Ayşe');
      expect(text('takeawayPhoneField'), '+905321112233');
      expect(text('deliveryStreetField'), 'Bahariye Caddesi');
      expect(find.textContaining('Caferağa, Moda Caddesi'), findsOneWidget,
          reason: 'older addresses are offered as chips');
      expect(find.byKey(const Key('selectedCustomerNotice')), findsNothing);
    });

    testWidgets(
        'uygulama musterisi secilince telefon maskeli kalir ve aciklanir',
        (tester) async {
      final gateway = await _pump(tester);
      gateway.searchResults = const [
        PosCustomerBookEntry(
          isFromBook: false,
          id: 'uid-1',
          displayName: 'Zeynep Kaya',
          firstName: 'Zeynep',
          lastName: 'Kaya',
          phoneNumber: null,
          phoneMasked: '***********44',
          addresses: [],
          linkedCustomerId: 'uid-1',
        ),
      ];

      await _search(tester, 'zeynep');
      await tester.tap(find.text('Zeynep Kaya'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('selectedCustomerNotice')), findsOneWidget);
      expect(
          tester
              .widget<TextField>(find.byKey(const Key('takeawayPhoneField')))
              .controller!
              .text,
          '');
    });

    testWidgets('kayit bulunamazsa tek tikla yeni musteri girilir',
        (tester) async {
      await _pump(tester);

      await _search(tester, 'Yok');

      expect(find.text('Kayıtlı müşteri bulunamadı.'), findsOneWidget);
      await tester.tap(find.text('Yeni Müşteri Gir'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('customerSearchResults')), findsNothing);
    });
  });
}
