import 'package:abakus_one_v2/features/takeaway/presentation/widgets/scheduled_orders_count_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ScheduledOrdersCountBadge', () {
    testWidgets('renders nothing when count is zero', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: ScheduledOrdersCountBadge(count: 0)),
      ));
      expect(find.byType(SizedBox), findsOneWidget);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('renders the count when non-zero', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: ScheduledOrdersCountBadge(count: 3)),
      ));
      expect(find.text('3'), findsOneWidget);
    });
  });
}
