import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:abakus_one_v2/features/pos/presentation/providers/pos_workspace_providers.dart';
import 'package:abakus_one_v2/features/printing/domain/receipt_codepage.dart';

/// 2026-11-06 physical print test follow-up — `ReceiptPrinterSettings`
/// gained a persisted `codepage` choice (see `ReceiptCodepage`'s own doc
/// comment for why this can't be auto-detected from software).
void main() {
  group('ReceiptPrinterSettings.codepage', () {
    test('defaults to wpc1254 when nothing has ever been stored', () async {
      SharedPreferences.setMockInitialValues({});
      final settings =
          ReceiptPrinterSettings(await SharedPreferences.getInstance());

      expect(settings.codepage, ReceiptCodepage.wpc1254);
    });

    test('setCodepage then reading codepage round-trips the value', () async {
      SharedPreferences.setMockInitialValues({});
      final settings =
          ReceiptPrinterSettings(await SharedPreferences.getInstance());

      await settings.setCodepage(ReceiptCodepage.pc857);

      expect(settings.codepage, ReceiptCodepage.pc857);
    });

    test(
        'a durable choice survives a fresh SharedPreferences.getInstance() '
        'call — proves persistence, not just in-memory state', () async {
      SharedPreferences.setMockInitialValues({});
      final prefsBefore = await SharedPreferences.getInstance();
      await ReceiptPrinterSettings(prefsBefore)
          .setCodepage(ReceiptCodepage.pc857);

      final prefsAfter = await SharedPreferences.getInstance();
      final reopened = ReceiptPrinterSettings(prefsAfter);

      expect(reopened.codepage, ReceiptCodepage.pc857);
    });
  });
}
