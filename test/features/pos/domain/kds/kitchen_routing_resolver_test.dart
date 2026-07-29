import 'package:abakus_one_v2/features/pos/domain/kds/kitchen_routing_resolver.dart';
import 'package:abakus_one_v2/features/pos/domain/kds/kitchen_routing_rule.dart';
import 'package:abakus_one_v2/features/pos/domain/kds/kitchen_station.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('KitchenRoutingResolver.resolve', () {
    test('resolves to shared when no rules are configured', () {
      final station = KitchenRoutingResolver.resolve(rules: const []);
      expect(station, KitchenStation.shared);
    });

    test('resolves to shared when no rule matches', () {
      final rules = [
        const KitchenRoutingRule(
          id: 'r1',
          branchId: 'branch-1',
          priority: 1,
          criteria: KitchenRoutingCriteria(productId: 'product-99'),
          targetStation: KitchenStation.hot,
        ),
      ];
      final station = KitchenRoutingResolver.resolve(
        rules: rules,
        productId: 'product-1',
      );
      expect(station, KitchenStation.shared);
    });

    test('matches by productId', () {
      final rules = [
        const KitchenRoutingRule(
          id: 'r1',
          branchId: 'branch-1',
          priority: 1,
          criteria: KitchenRoutingCriteria(productId: 'product-1'),
          targetStation: KitchenStation.hot,
        ),
      ];
      final station = KitchenRoutingResolver.resolve(
        rules: rules,
        productId: 'product-1',
      );
      expect(station, KitchenStation.hot);
    });

    test('evaluates rules in ascending priority order, first match wins', () {
      final rules = [
        const KitchenRoutingRule(
          id: 'r-low-priority',
          branchId: 'branch-1',
          priority: 5,
          criteria: KitchenRoutingCriteria(categoryId: 'drinks'),
          targetStation: KitchenStation.beverage,
        ),
        const KitchenRoutingRule(
          id: 'r-high-priority',
          branchId: 'branch-1',
          priority: 1,
          criteria: KitchenRoutingCriteria(categoryId: 'drinks'),
          targetStation: KitchenStation.dessert,
        ),
      ];
      final station = KitchenRoutingResolver.resolve(
        rules: rules,
        categoryId: 'drinks',
      );
      expect(station, KitchenStation.dessert);
    });

    test('matches by modifier code among a set', () {
      final rules = [
        const KitchenRoutingRule(
          id: 'r1',
          branchId: 'branch-1',
          priority: 1,
          criteria: KitchenRoutingCriteria(modifierCode: 'extra-cheese'),
          targetStation: KitchenStation.hot,
        ),
      ];
      final station = KitchenRoutingResolver.resolve(
        rules: rules,
        modifierCodes: {'extra-cheese', 'no-onion'},
      );
      expect(station, KitchenStation.hot);
    });

    test('AND-combines multiple criteria fields on one rule', () {
      final rules = [
        const KitchenRoutingRule(
          id: 'r1',
          branchId: 'branch-1',
          priority: 1,
          criteria: KitchenRoutingCriteria(
              categoryId: 'drinks', channelName: 'delivery'),
          targetStation: KitchenStation.beverage,
        ),
      ];
      expect(
        KitchenRoutingResolver.resolve(
          rules: rules,
          categoryId: 'drinks',
          channelName: 'takeaway',
        ),
        KitchenStation.shared,
      );
      expect(
        KitchenRoutingResolver.resolve(
          rules: rules,
          categoryId: 'drinks',
          channelName: 'delivery',
        ),
        KitchenStation.beverage,
      );
    });
  });
}
