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
import 'package:abakus_one_v2/features/pos/domain/delivery_neighborhood_clusterer.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

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

Order _buildOrder(String id, {String? neighborhoodName}) {
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
    status: OrderStatus.ready,
    channel: OrderChannel.delivery,
    branchId: 'branch-1',
    restaurantId: 'restaurant-1',
    lines: [line],
    pricing: PriceCalculator.calculate(lines: [line], currency: Currency.tryLira),
    timestamps: OrderTimestamps(created: DateTime(2026, 1, 1)),
    deliveryAddressSnapshot: _addressWithNeighborhood(neighborhoodName),
  );
}

void main() {
  group('DeliveryNeighborhoodClusterer.cluster', () {
    test('groups orders by neighborhoodName, largest cluster first', () {
      final orders = [
        _buildOrder('o1', neighborhoodName: 'Fulya'),
        _buildOrder('o2', neighborhoodName: 'Dikilitaş'),
        _buildOrder('o3', neighborhoodName: 'Fulya'),
        _buildOrder('o4', neighborhoodName: 'Fulya'),
      ];

      final clusters = DeliveryNeighborhoodClusterer.cluster(orders);

      expect(clusters.length, 2);
      expect(clusters[0].neighborhoodName, 'Fulya');
      expect(clusters[0].orders.length, 3);
      expect(clusters[1].neighborhoodName, 'Dikilitaş');
      expect(clusters[1].orders.length, 1);
    });

    test('a null neighborhoodName goes to its own ungrouped bucket, sorted last regardless of size', () {
      final orders = [
        _buildOrder('o1', neighborhoodName: null),
        _buildOrder('o2', neighborhoodName: null),
        _buildOrder('o3', neighborhoodName: null),
        _buildOrder('o4', neighborhoodName: 'Fulya'),
      ];

      final clusters = DeliveryNeighborhoodClusterer.cluster(orders);

      expect(clusters.length, 2);
      expect(clusters[0].neighborhoodName, 'Fulya');
      expect(clusters[1].neighborhoodName, isNull);
      expect(clusters[1].orders.length, 3);
    });

    test('ties are broken alphabetically by neighborhood name', () {
      final orders = [
        _buildOrder('o1', neighborhoodName: 'Dikilitaş'),
        _buildOrder('o2', neighborhoodName: 'Fulya'),
      ];

      final clusters = DeliveryNeighborhoodClusterer.cluster(orders);

      expect(clusters.map((c) => c.neighborhoodName).toList(), ['Dikilitaş', 'Fulya']);
    });

    test('empty input yields empty output', () {
      expect(DeliveryNeighborhoodClusterer.cluster(const []), isEmpty);
    });
  });
}
