import 'package:abakus_one_v2/features/crm/domain/visits/visit_qualification_rule.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VisitQualificationRule', () {
    test('a completed delivery order qualifies', () {
      expect(
        VisitQualificationRule.qualifies(
          channel: OrderChannel.delivery,
          status: OrderStatus.completed,
        ),
        isTrue,
      );
    });

    test(
        'dine-in qualification follows the documented rule — a completed '
        'dine-in order qualifies exactly like any other channel', () {
      expect(
        VisitQualificationRule.qualifies(
          channel: OrderChannel.dineInQr,
          status: OrderStatus.completed,
        ),
        isTrue,
      );
      expect(
        VisitQualificationRule.qualifies(
          channel: OrderChannel.dineInStaff,
          status: OrderStatus.completed,
        ),
        isTrue,
      );
    });

    test('a non-completed order never qualifies, regardless of channel', () {
      for (final channel in OrderChannel.values) {
        for (final status in OrderStatus.values) {
          if (status == OrderStatus.completed) continue;
          expect(
            VisitQualificationRule.qualifies(channel: channel, status: status),
            isFalse,
            reason: 'channel: $channel, status: $status',
          );
        }
      }
    });

    test('a cancelled order never qualifies', () {
      expect(
        VisitQualificationRule.qualifies(
          channel: OrderChannel.delivery,
          status: OrderStatus.cancelled,
        ),
        isFalse,
      );
    });

    test('a refunded order never qualifies', () {
      expect(
        VisitQualificationRule.qualifies(
          channel: OrderChannel.delivery,
          status: OrderStatus.refunded,
        ),
        isFalse,
      );
    });
  });
}
