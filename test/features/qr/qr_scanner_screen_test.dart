import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/qr/presentation/screens/qr_scanner_screen.dart';

/// Structural coverage only — `MobileScanner` (real camera hardware) can't
/// be meaningfully driven from a widget test (no platform implementation
/// in the test harness). What *can* and must be verified here: the screen
/// renders without throwing, shows real scan-guidance text (not the old
/// static explainer this screen used to be), and never shows a fake
/// success state. The actual scan -> resolve -> table-context pipeline is
/// covered at the provider/use-case level (`resolve_table_qr_token_test
/// .dart`, `active_table_context_provider_test.dart`) and manually on a
/// real device (see this feature's final report).
void main() {
  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: QrScannerScreen()),
      ),
    );
    await tester.pump();
  }

  testWidgets('kamera ekrani hatasiz acilir ve gercek tarama arayuzu gosterir',
      (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(find.text('QR ile Sipariş'), findsOneWidget);
    expect(
      find.textContaining('Masandaki QR kodu kare içine hizala'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'artik sahte "yakinda eklenecek" mesaji yoktur - gercek tarama arayuzudur',
    (tester) async {
      await pumpScreen(tester);

      expect(
        find.textContaining('bu sürümde henüz aktif değil'),
        findsNothing,
      );
      expect(find.text('QR Kodu Tara'), findsNothing);
    },
  );
}
