import 'package:abakus_one_v2/features/courier/domain/delivery/same_destination_detector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SameDestinationDetector.normalize', () {
    test('trims, lowercases, and collapses whitespace', () {
      expect(
        SameDestinationDetector.normalize('  Ev - Kadıköy,   Moda Cad. 12  '),
        'ev kadıköy moda cad 12',
      );
    });
  });

  group('SameDestinationDetector.detectGroups', () {
    test(
        'two deliveries with the same normalized destination form a '
        'group', () {
      final groups = SameDestinationDetector.detectGroups(const [
        DeliveryDestinationEntry(
            deliveryId: 'd1', destinationText: 'Ev - Kadıköy, Moda Cad. 12'),
        DeliveryDestinationEntry(
            deliveryId: 'd2', destinationText: 'ev-kadıköy moda cad 12'),
      ]);
      expect(groups, hasLength(1));
      expect(groups.single.toSet(), {'d1', 'd2'});
    });

    test('a unique destination never forms a group', () {
      final groups = SameDestinationDetector.detectGroups(const [
        DeliveryDestinationEntry(deliveryId: 'd1', destinationText: 'Adres A'),
        DeliveryDestinationEntry(deliveryId: 'd2', destinationText: 'Adres B'),
      ]);
      expect(groups, isEmpty);
    });

    test(
        'empty/blank destination text is never grouped, even with '
        'another blank one', () {
      final groups = SameDestinationDetector.detectGroups(const [
        DeliveryDestinationEntry(deliveryId: 'd1', destinationText: ''),
        DeliveryDestinationEntry(deliveryId: 'd2', destinationText: '   '),
      ]);
      expect(groups, isEmpty);
    });

    test(
        'three deliveries sharing one destination form a single group of '
        'three', () {
      final groups = SameDestinationDetector.detectGroups(const [
        DeliveryDestinationEntry(deliveryId: 'd1', destinationText: 'Adres A'),
        DeliveryDestinationEntry(deliveryId: 'd2', destinationText: 'Adres A'),
        DeliveryDestinationEntry(deliveryId: 'd3', destinationText: 'Adres A'),
      ]);
      expect(groups, hasLength(1));
      expect(groups.single.toSet(), {'d1', 'd2', 'd3'});
    });
  });
}
