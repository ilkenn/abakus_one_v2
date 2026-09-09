import 'package:abakus_one_v2/features/takeaway/domain/models/branch_takeaway_settings.dart';
import 'package:abakus_one_v2/features/takeaway/presentation/widgets/takeaway_operation_status_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TakeawayOperationStatusBadge', () {
    testWidgets('renders "Aktif" for active', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: TakeawayOperationStatusBadge(status: TakeawayOperationStatus.active),
        ),
      ));
      expect(find.text('Aktif'), findsOneWidget);
    });

    testWidgets('renders "Yoğun (+30 dk)" for busy with a delay', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: TakeawayOperationStatusBadge(
            status: TakeawayOperationStatus.busy,
            busyDelayMinutes: 30,
          ),
        ),
      ));
      expect(find.text('Yoğun (+30 dk)'), findsOneWidget);
    });

    testWidgets('renders "Kapalı" for paused', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: TakeawayOperationStatusBadge(status: TakeawayOperationStatus.paused),
        ),
      ));
      expect(find.text('Kapalı'), findsOneWidget);
    });

    testWidgets('invokes onTap when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TakeawayOperationStatusBadge(
            status: TakeawayOperationStatus.active,
            onTap: () => tapped = true,
          ),
        ),
      ));
      await tester.tap(find.byType(TakeawayOperationStatusBadge));
      expect(tapped, isTrue);
    });

    testWidgets('is not tappable when onTap is null', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: TakeawayOperationStatusBadge(status: TakeawayOperationStatus.active),
        ),
      ));
      expect(find.byType(InkWell), findsNothing);
    });
  });
}
