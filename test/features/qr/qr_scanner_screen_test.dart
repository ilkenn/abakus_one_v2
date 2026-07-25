import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/qr/presentation/screens/qr_scanner_screen.dart';

void main() {
  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: QrScannerScreen()),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('bilgilendirme icerigini ve nasil calisir adimlarini gosterir', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(find.text('Masandaki QR Kodu Okut'), findsOneWidget);
    expect(find.text('Nasıl Çalışır?'), findsOneWidget);
    expect(find.text('QR kodu tara'), findsOneWidget);
    expect(find.text('Menüden seç'), findsOneWidget);
    expect(find.text('Siparişini onayla'), findsOneWidget);
  });

  testWidgets(
    'QR Kodu Tara butonu sahte basari yerine durumu acikca bildirir',
    (tester) async {
      await pumpScreen(tester);

      final buttonLabel = find.text('QR Kodu Tara');
      await tester.dragUntilVisible(
        buttonLabel,
        find.byType(Scrollable),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      await tester.tap(buttonLabel);
      await tester.pump();

      expect(
        find.text(
          'Kamera ile QR tarama bu sürümde henüz aktif değil. Yakında eklenecek.',
        ),
        findsOneWidget,
      );
    },
  );
}
