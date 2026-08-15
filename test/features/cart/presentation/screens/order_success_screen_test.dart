import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/cart/presentation/screens/order_success_screen.dart';

/// Faz D.4 — `takeawayPickupTime` is now optional even when
/// `takeawayBranchName` is set, to serve the Gel Al QR guest scenario
/// (always ASAP, `pickupTime` forced `null` server-side). Every existing
/// caller (Faz C's authenticated `TakeawayCheckoutScreen`, which still
/// always supplies a real pickup time) keeps behaving exactly as before —
/// these tests only exercise the new null-pickup-time branch and the
/// pre-existing branches it must not disturb.
void main() {
  Future<void> pumpScreen(
    WidgetTester tester, {
    String? takeawayBranchName,
    DateTime? takeawayPickupTime,
    String? dineInBranchName,
    String? dineInTableName,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: OrderSuccessScreen(
          orderId: 'order-123',
          takeawayBranchName: takeawayBranchName,
          takeawayPickupTime: takeawayPickupTime,
          dineInBranchName: dineInBranchName,
          dineInTableName: dineInTableName,
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
      'takeawayPickupTime null (Gel Al QR guest, ASAP) — hazırlanıyor '
      'kopyası gösterilir, spesifik bir saat gösterilmez', (tester) async {
    await pumpScreen(tester, takeawayBranchName: 'Abaküs Ortaköy');

    expect(find.text('Abaküs Ortaköy'), findsOneWidget);
    expect(
      find.textContaining('kasadan teslim alabilirsin'),
      findsOneWidget,
    );
    expect(find.textContaining('Teslim alma saati:'), findsNothing);
    expect(find.text('Siparişin Alındı!'), findsOneWidget);
  });

  testWidgets(
      'takeawayPickupTime dolu (mevcut authenticated Faz C akışı) — '
      'spesifik saat gösterilir, davranış değişmedi', (tester) async {
    await pumpScreen(
      tester,
      takeawayBranchName: 'Abaküs Ortaköy',
      takeawayPickupTime: DateTime(2026, 8, 11, 14, 30),
    );

    expect(find.textContaining('Teslim alma saati: 14:30'), findsOneWidget);
    expect(
      find.textContaining('kasadan teslim alabilirsin'),
      findsNothing,
    );
  });

  testWidgets('dine-in davranışı değişmedi', (tester) async {
    await pumpScreen(
      tester,
      dineInBranchName: 'Abaküs Ortaköy',
      dineInTableName: 'Masa 4',
    );

    expect(find.text('Abaküs Ortaköy · Masa 4'), findsOneWidget);
    expect(find.textContaining('masana hazırlanıyor'), findsOneWidget);
  });

  testWidgets('varsayılan (delivery) davranışı değişmedi', (tester) async {
    await pumpScreen(tester);

    expect(find.text('Siparişiniz Alındı!'), findsOneWidget);
    expect(
      find.textContaining('Taptaze malzemelerle'),
      findsOneWidget,
    );
  });

  testWidgets('Gel Al guest siparişinde loyalty/Boncuk asla ima edilmez',
      (tester) async {
    await pumpScreen(tester, takeawayBranchName: 'Abaküs Ortaköy');

    expect(find.textContaining('Boncuk'), findsNothing);
    expect(find.textContaining('puan'), findsNothing);
    expect(find.textContaining('kazandın'), findsNothing);
  });
}
