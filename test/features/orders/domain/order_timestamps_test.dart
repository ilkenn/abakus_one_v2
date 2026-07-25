import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_status.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_timestamps.dart';

void main() {
  test('yeni OrderTimestamps yalnizca created ile baslar', () {
    final created = DateTime(2026, 7, 20, 12, 0);
    final timestamps = OrderTimestamps(created: created);

    expect(timestamps.created, created);
    expect(timestamps.confirmed, isNull);
    expect(timestamps.preparing, isNull);
    expect(timestamps.ready, isNull);
    expect(timestamps.served, isNull);
    expect(timestamps.completed, isNull);
    expect(timestamps.cancelled, isNull);
  });

  group('recordedAt', () {
    test('confirmed durumu icin confirmed alanini gunceller', () {
      final base = OrderTimestamps(created: DateTime(2026, 7, 20, 12, 0));
      final at = DateTime(2026, 7, 20, 12, 5);

      final updated = base.recordedAt(OrderStatus.confirmed, at);

      expect(updated.confirmed, at);
      expect(updated.preparing, isNull);
    });

    test('takip edilen 7 asamayi sirayla dogru alana yazar', () {
      var timestamps = OrderTimestamps(created: DateTime(2026, 7, 20, 12, 0));
      final confirmedAt = DateTime(2026, 7, 20, 12, 2);
      final preparingAt = DateTime(2026, 7, 20, 12, 5);
      final readyAt = DateTime(2026, 7, 20, 12, 15);
      final servedAt = DateTime(2026, 7, 20, 12, 20);
      final completedAt = DateTime(2026, 7, 20, 12, 30);

      timestamps = timestamps
          .recordedAt(OrderStatus.confirmed, confirmedAt)
          .recordedAt(OrderStatus.preparing, preparingAt)
          .recordedAt(OrderStatus.ready, readyAt)
          .recordedAt(OrderStatus.served, servedAt)
          .recordedAt(OrderStatus.completed, completedAt);

      expect(timestamps.confirmed, confirmedAt);
      expect(timestamps.preparing, preparingAt);
      expect(timestamps.ready, readyAt);
      expect(timestamps.served, servedAt);
      expect(timestamps.completed, completedAt);
      expect(timestamps.cancelled, isNull);
    });

    test(
        'takip edilmeyen durumlar (orn. outForDelivery) hicbir alani degistirmez',
        () {
      final base = OrderTimestamps(created: DateTime(2026, 7, 20, 12, 0));

      final unchanged = base.recordedAt(
        OrderStatus.outForDelivery,
        DateTime(2026, 7, 20, 12, 10),
      );

      expect(unchanged.confirmed, isNull);
      expect(unchanged.preparing, isNull);
      expect(unchanged.ready, isNull);
      expect(unchanged.served, isNull);
      expect(unchanged.completed, isNull);
      expect(unchanged.cancelled, isNull);
      expect(unchanged.created, base.created);
    });

    test('cancelled durumu cancelled alanini gunceller', () {
      final base = OrderTimestamps(created: DateTime(2026, 7, 20, 12, 0));
      final cancelledAt = DateTime(2026, 7, 20, 12, 3);

      final updated = base.recordedAt(OrderStatus.cancelled, cancelledAt);

      expect(updated.cancelled, cancelledAt);
    });
  });
}
