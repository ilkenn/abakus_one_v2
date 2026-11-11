import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/features/admin/data/tenant_customer_directory_gateway.dart';
import 'package:abakus_one_v2/features/admin/presentation/providers/admin_dependencies_provider.dart';
import 'package:abakus_one_v2/features/courier/domain/identity/courier.dart';
import 'package:abakus_one_v2/features/courier/domain/identity/courier_registry_status.dart';
import 'package:abakus_one_v2/features/menu/domain/models/menu_product.dart';
import 'package:abakus_one_v2/features/menu/presentation/providers/menu_catalog_provider.dart';
import 'package:abakus_one_v2/features/pos/data/pos_action_gateway.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/courier_dispatch_dependencies_provider.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/pos_workspace_providers.dart';
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

class _FakeCustomerDirectory implements TenantCustomerDirectoryGateway {
  List<TenantCustomerSearchResult> results = const [];
  List<Map<String, dynamic>> addresses = const [];
  String? lastNamePrefix;
  String? lastPhoneNumber;

  @override
  Future<List<TenantCustomerSearchResult>> search({
    required String organizationId,
    String? phoneNumber,
    String? namePrefix,
  }) async {
    lastNamePrefix = namePrefix;
    lastPhoneNumber = phoneNumber;
    return results;
  }

  @override
  Future<TenantCustomerDetail> getDetail({
    required String organizationId,
    required String customerId,
  }) async =>
      TenantCustomerDetail(
        id: customerId,
        displayName: 'Ayşe Demir',
        phoneMasked: '******12',
        registrationDate: DateTime(2026),
        lastActivityAt: DateTime(2026),
        accountState: 'active',
        relatedBranchIds: const ['branch-1'],
        lastOrderAt: null,
        totalOrderCount: 3,
        orderAddressSnapshots: addresses,
        restrictionStatus: 'none',
        restrictionReasonMessage: null,
        marketingConsent: 'notCaptured',
      );

  @override
  Future<TenantCustomerListPage> list({
    required String organizationId,
    String? namePrefix,
    String? cursor,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> setRestriction({
    required String organizationId,
    required String customerId,
    required bool restrict,
    required String reasonCode,
    required String reasonMessage,
  }) =>
      throw UnimplementedError();
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

class _Fakes {
  _Fakes(this.orders, this.customers);
  final _FakeSubmitTakeawayOrderGateway orders;
  final _FakeCustomerDirectory customers;
}

Future<_Fakes> _pump(
  WidgetTester tester, {
  PosPhoneOrderMode mode = PosPhoneOrderMode.takeaway,
  List<Courier> couriers = const [],
}) async {
  await tester.binding.setSurfaceSize(const Size(1400, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final orders = _FakeSubmitTakeawayOrderGateway();
  final customers = _FakeCustomerDirectory();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        submitTakeawayOrderGatewayProvider.overrideWithValue(orders),
        tenantCustomerDirectoryGatewayProvider.overrideWithValue(customers),
        menuProductsProvider.overrideWithValue(const [_simpleProduct]),
        topSellingProductsProvider.overrideWith((ref, ctx) async => const []),
        allCouriersForBranchProvider
            .overrideWith((ref, branchId) => Stream.value(couriers)),
      ],
      child: MaterialApp(
        home: PosNewTakeawayOrderScreen(ctx: _ctx, initialMode: mode),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Fakes(orders, customers);
}

/// Adds the test product through the shared catalog's name search.
Future<void> _addProduct(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('productSearchField')), 'Paket');
  await tester.pump();
  await tester.tap(find.descendant(
    of: find.byType(GridView),
    matching: find.text('Paket Kutu'),
  ));
  await tester.pump();
}

Future<void> _fillContact(WidgetTester tester) async {
  await tester.enterText(
      find.byKey(const Key('takeawayFirstNameField')), 'Ahmet');
  await tester.enterText(
      find.byKey(const Key('takeawayLastNameField')), 'Yılmaz');
  await tester.enterText(
      find.byKey(const Key('takeawayPhoneField')), '+905551112233');
}

void main() {
  group('Gel-Al', () {
    testWidgets(
        'ad/soyad/telefon ve en az bir urun olmadan Siparisi Onayla hicbir '
        'sey gondermez, hata gosterir', (tester) async {
      final fakes = await _pump(tester);

      await tester.tap(find.byKey(const Key('submitNewTakeawayOrderButton')));
      await tester.pump();

      expect(fakes.orders.staffEntryCallCount, 0);
      expect(find.textContaining('zorunludur'), findsOneWidget);
    });

    testWidgets(
        'katalogdan urun secip musteri bilgisi girilince "Siparişi Onayla & '
        'Mutfağa İlet" submitStaffEntryOrder cagirir ve kapanir',
        (tester) async {
      final fakes = await _pump(tester);
      await _fillContact(tester);
      await _addProduct(tester);
      await _addProduct(tester);

      expect(tester.widget<Text>(find.byKey(const Key('phoneOrderTotal'))).data,
          '200 TL',
          reason: 'the same product twice merges into one line of 2');
      await tester.tap(find.byKey(const Key('submitNewTakeawayOrderButton')));
      await tester.pumpAndSettle();

      expect(fakes.orders.staffEntryCallCount, 1);
      expect(fakes.orders.lastContactFirstName, 'Ahmet');
      expect(fakes.orders.lastContactPhone, '+905551112233');
      final item = fakes.orders.lastItems!.single as TakeawayProductItem;
      expect(item.productId, 'prod_test_1');
      expect(item.quantity, 2);
    });

    testWidgets(
        'gateway hata firlatinca sepet/alanlar korunur, hata gosterilir',
        (tester) async {
      final fakes = await _pump(tester);
      fakes.orders.throwOnStaffEntry =
          const SubmitTakeawayOrderException('internal', 'Sunucu hatası.');
      await _fillContact(tester);
      await _addProduct(tester);

      await tester.tap(find.byKey(const Key('submitNewTakeawayOrderButton')));
      await tester.pumpAndSettle();

      expect(find.text('Sunucu hatası.'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('phoneOrderTotal'))).data,
          '100 TL',
          reason: 'sepet korunmali, hata sonrasi kaybolmamali');
    });

    testWidgets(
        'Gel-Al modunda adres, kurye ve kapida odeme alanlari gizlidir; mutfak '
        'notu Faz 2 aciklamasiyla pasiftir', (tester) async {
      await _pump(tester);

      expect(find.byKey(const Key('deliveryNeighborhoodField')), findsNothing);
      expect(find.byKey(const Key('courierNoteField')), findsNothing);
      expect(find.text('Kapıda Nakit'), findsNothing);
      expect(find.byKey(const Key('printCourierSlipButton')), findsNothing);
      final kitchenNote =
          tester.widget<TextField>(find.byKey(const Key('kitchenNoteField')));
      expect(kitchenNote.enabled, isFalse);
    });
  });

  group('Paket Servis', () {
    final couriers = [
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

    testWidgets(
        'mod gecisi adres, kurye notu, kapida odeme ve kurye rozetlerini acar',
        (tester) async {
      await _pump(tester, couriers: couriers);

      await tester.tap(find.text('Paket Servis'));
      await tester.pumpAndSettle();

      expect(
          find.byKey(const Key('deliveryNeighborhoodField')), findsOneWidget);
      expect(find.byKey(const Key('courierNoteField')), findsOneWidget);
      for (final method in [
        'Kapıda Nakit',
        'Kapıda POS',
        'Kapıda Yemek Kartı'
      ]) {
        expect(find.text(method), findsOneWidget, reason: method);
      }
      expect(find.widgetWithText(ChoiceChip, 'Ahmet'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Mehmet'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Arşivli'), findsNothing,
          reason: 'only active shop couriers are offered');
      final pool = tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Kurye Havuzu'));
      expect(pool.onSelected, isNull, reason: 'the courier pool is Faz 3');

      await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Mehmet'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Mehmet'));
      await tester.pump();
      expect(
          tester
              .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Mehmet'))
              .selected,
          isTrue);
    });

    testWidgets(
        'paket siparisi gonderimi ve kurye fisi Faz 2 aciklamasiyla pasiftir; '
        'hicbir sey gonderilmez', (tester) async {
      final fakes = await _pump(tester, mode: PosPhoneOrderMode.delivery);
      await _fillContact(tester);
      await _addProduct(tester);

      expect(find.byKey(const Key('deliverySubmitNotice')), findsOneWidget);
      final submit = tester.widget<ElevatedButton>(
          find.byKey(const Key('submitNewTakeawayOrderButton')));
      expect(submit.onPressed, isNull);
      final slip = tester.widget<OutlinedButton>(
          find.byKey(const Key('printCourierSlipButton')));
      expect(slip.onPressed, isNull);
      expect(fakes.orders.staffEntryCallCount, 0);
    });
  });

  group('Müşteri Ara', () {
    testWidgets(
        'isimle arama kayitli musterileri listeler; secilen musterinin adi ve '
        'onceki adresi otomatik dolar', (tester) async {
      final fakes = await _pump(tester, mode: PosPhoneOrderMode.delivery);
      fakes.customers
        ..results = const [
          TenantCustomerSearchResult(
              id: 'cust-1', displayName: 'Ayşe Demir', phoneMasked: '******12'),
        ]
        ..addresses = const [
          {
            'label': 'Ev',
            'neighborhoodName': 'Caferağa',
            'streetName': 'Moda Caddesi',
            'buildingNo': '12',
            'apartmentNo': '4',
            'addressDescription': 'Eczanenin üstü',
          },
        ];

      await tester.enterText(
          find.byKey(const Key('customerSearchField')), 'Ayşe');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(fakes.customers.lastNamePrefix, 'Ayşe');
      expect(find.text('******12'), findsOneWidget);
      await tester.tap(find.text('Ayşe Demir'));
      await tester.pumpAndSettle();

      TextField field(String key) =>
          tester.widget<TextField>(find.byKey(Key(key)));
      expect(field('takeawayFirstNameField').controller!.text, 'Ayşe');
      expect(field('takeawayLastNameField').controller!.text, 'Demir');
      expect(field('deliveryNeighborhoodField').controller!.text, 'Caferağa');
      expect(field('deliveryStreetField').controller!.text, 'Moda Caddesi');
      expect(find.byKey(const Key('selectedCustomerNotice')), findsOneWidget,
          reason: 'the masked phone is explained');
      expect(find.textContaining('Ev — Caferağa'), findsOneWidget,
          reason: 'previous addresses are offered as chips');
    });

    testWidgets('telefonla arama phoneNumber gonderir', (tester) async {
      final fakes = await _pump(tester);

      await tester.enterText(
          find.byKey(const Key('customerSearchField')), '0532 111 22 33');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(fakes.customers.lastPhoneNumber, '05321112233');
      expect(fakes.customers.lastNamePrefix, isNull);
    });

    testWidgets('kayit bulunamazsa tek tikla yeni musteri girisi yapilabilir',
        (tester) async {
      await _pump(tester);

      await tester.enterText(
          find.byKey(const Key('customerSearchField')), 'Zeynep');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(find.text('Kayıtlı müşteri bulunamadı.'), findsOneWidget);
      await tester.tap(find.text('Yeni Müşteri Gir'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('customerSearchResults')), findsNothing);
      expect(
          tester
              .widget<TextField>(
                  find.byKey(const Key('takeawayFirstNameField')))
              .focusNode!
              .hasFocus,
          isTrue);
    });
  });
}
