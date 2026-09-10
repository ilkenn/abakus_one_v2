import 'package:abakus_one_v2/features/orders/domain/models/delivery_address_snapshot.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_line.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_number.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_status.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_timestamps.dart';
import 'package:abakus_one_v2/features/orders/domain/pricing/price_calculator.dart';
import 'package:abakus_one_v2/features/orders/domain/pricing/tax_policy.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/courier_dispatch_dependencies_provider.dart';
import 'package:abakus_one_v2/features/pos/presentation/screens/delivery_order_dispatch_screen.dart';
import 'package:abakus_one_v2/shared/models/courier_type.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _branchId = 'branch-1';

DeliveryAddressSnapshot? _addressWithNeighborhood(String? neighborhoodName) {
  if (neighborhoodName == null) return null;
  return DeliveryAddressSnapshot(
    savedAddressId: 'address-1',
    label: 'Ev',
    provinceId: 'il-34',
    provinceName: 'İstanbul',
    districtId: 'ilce-sisli',
    districtName: 'Şişli',
    neighborhoodId: 'mah-$neighborhoodName',
    neighborhoodName: neighborhoodName,
    buildingNo: '1',
    apartmentNo: '1',
    latitude: 41.0,
    longitude: 29.0,
    providerSource: 'manual',
    serverVerifiedAt: DateTime(2026, 1, 1),
  );
}

Order _buildOrder(
  String id, {
  String? neighborhoodName,
  String? merchantId,
  String? merchantName,
  CourierType? courierType,
  OrderStatus status = OrderStatus.ready,
}) {
  final line = OrderLine.create(
    productId: 'p1',
    productName: 'Test',
    quantity: 1,
    unitPrice: Money.fromWhole(100, Currency.tryLira),
    taxRate: TaxPolicy.defaultRate,
  );
  return Order(
    id: OrderId(id),
    orderNumber: OrderNumber('A-$id'),
    status: status,
    channel: OrderChannel.delivery,
    branchId: _branchId,
    restaurantId: 'restaurant-1',
    lines: [line],
    pricing: PriceCalculator.calculate(lines: [line], currency: Currency.tryLira),
    timestamps: OrderTimestamps(created: DateTime(2026, 1, 1)),
    deliveryAddressSnapshot: _addressWithNeighborhood(neighborhoodName),
    merchantId: merchantId,
    merchantName: merchantName,
    courierType: courierType,
    contactFirstName: 'Ada',
    contactLastName: 'Yılmaz',
  );
}

Future<void> _pumpScreen(WidgetTester tester, List<Order> orders) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        assignableDeliveryOrdersProvider(_branchId).overrideWith((ref) => Stream.value(orders)),
        allCouriersForBranchProvider(_branchId).overrideWith((ref) => Stream.value(const [])),
      ],
      child: const MaterialApp(
        home: DeliveryOrderDispatchScreen(organizationId: 'org-1', branchId: _branchId),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('DeliveryOrderDispatchScreen', () {
    testWidgets('renders one cluster card per neighborhood, largest first', (tester) async {
      await _pumpScreen(tester, [
        _buildOrder('o1', neighborhoodName: 'Fulya'),
        _buildOrder('o2', neighborhoodName: 'Dikilitaş'),
        _buildOrder('o3', neighborhoodName: 'Fulya'),
      ]);

      expect(find.text('Fulya Bölgesi (2 Paket)'), findsOneWidget);
      expect(find.text('Dikilitaş Bölgesi (1 Paket)'), findsOneWidget);
    });

    testWidgets('shows "Kendi Dükkanımız" for an in-house order and the merchant name for a consortium order', (tester) async {
      await _pumpScreen(tester, [
        _buildOrder('o1', neighborhoodName: 'Fulya'),
        _buildOrder(
          'o2',
          neighborhoodName: 'Fulya',
          merchantId: 'merchant-a',
          merchantName: 'Dış Restoran A',
        ),
      ]);

      expect(find.text('Kendi Dükkanımız'), findsOneWidget);
      expect(find.text('Dış Restoran A'), findsOneWidget);
    });

    testWidgets('selecting two orders shows the batch-assign bar with the correct count', (tester) async {
      await _pumpScreen(tester, [
        _buildOrder('o1', neighborhoodName: 'Fulya'),
        _buildOrder('o2', neighborhoodName: 'Fulya'),
      ]);

      expect(find.text('2 Paket Seçildi'), findsNothing);

      final checkboxes = find.byType(Checkbox);
      expect(checkboxes, findsNWidgets(2));
      await tester.tap(checkboxes.at(0));
      await tester.pumpAndSettle();
      await tester.tap(checkboxes.at(1));
      await tester.pumpAndSettle();

      expect(find.text('2 Paket Seçildi'), findsOneWidget);
      expect(find.text('Tek Kuryeye Ata'), findsOneWidget);
    });

    testWidgets('a marketplace-carried order\'s checkbox is disabled and excluded from selection', (tester) async {
      await _pumpScreen(tester, [
        _buildOrder('o1', neighborhoodName: 'Fulya', courierType: CourierType.marketplace),
      ]);

      final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(checkbox.onChanged, isNull);
      expect(find.text('Pazaryeri Kuryesi Taşımaktadır'), findsOneWidget);
      expect(find.text('Kurye Ata'), findsNothing);
    });
  });
}
