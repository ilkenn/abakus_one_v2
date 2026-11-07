/// Gün Sonu (Kasa Kapanışı) — the receipt-printer transport boundary.
///
/// **Corrected 2026-11-06 (Adım 3)** — this file previously said "no real
/// ESC/POS transport exists in this app," which was true when it was
/// written but is now stale: the 2026-11-05 till-receipt feature wired a
/// real `RawPrinterAdapter`/`WindowsRawPrinterAdapter` (Windows
/// `winspool.drv`, same "POS80 Printer" queue), since reused for the
/// kitchen ticket too. [WindowsZReportPrinterAdapter] below reuses that
/// same real transport — no new dependency, no new architecture, the
/// identical pattern `PrintTableReceipt`/`PrintKitchenTicket` already use.
/// [UnconfiguredZReportPrinterAdapter] remains the honest fallback for
/// every platform `WindowsRawPrinterAdapter` doesn't cover.
library;

import 'dart:io' show Platform;

import '../../printing/data/windows_raw_printer_adapter.dart';
import '../../printing/domain/esc_pos_z_report_encoder.dart';
import '../../printing/domain/receipt_codepage.dart';
import '../domain/cash/z_report_content.dart';

class ZReportPrintResult {
  const ZReportPrintResult({required this.succeeded, required this.message});
  final bool succeeded;
  final String message;
}

abstract interface class ZReportPrinterAdapter {
  Future<ZReportPrintResult> print(
    ZReportContent content, {
    ReceiptCodepage codepage,
  });
}

/// The real implementation — encodes [ZReportContent] via
/// [EscPosZReportEncoder] and sends it to the configured Windows printer
/// through the same [RawPrinterAdapter] the till receipt/kitchen ticket
/// already use.
class WindowsZReportPrinterAdapter implements ZReportPrinterAdapter {
  const WindowsZReportPrinterAdapter({
    required this.rawPrinterAdapter,
    required this.printerName,
  });

  final RawPrinterAdapter rawPrinterAdapter;
  final String printerName;

  @override
  Future<ZReportPrintResult> print(
    ZReportContent content, {
    ReceiptCodepage codepage = ReceiptCodepage.wpc1254,
  }) async {
    try {
      final bytes = EscPosZReportEncoder.encode(content, codepage: codepage);
      await rawPrinterAdapter.printRaw(
        printerName: printerName,
        bytes: bytes,
        jobName: 'Z Raporu - ${content.sessionId}',
      );
      return const ZReportPrintResult(succeeded: true, message: 'Yazdırıldı.');
    } on RawPrinterException catch (e) {
      return ZReportPrintResult(succeeded: false, message: e.message);
    }
  }
}

/// The honest "no real printer transport on this platform" adapter —
/// what every non-Windows build actually has today. Never fabricates a
/// successful print.
class UnconfiguredZReportPrinterAdapter implements ZReportPrinterAdapter {
  const UnconfiguredZReportPrinterAdapter();

  @override
  Future<ZReportPrintResult> print(
    ZReportContent content, {
    ReceiptCodepage codepage = ReceiptCodepage.wpc1254,
  }) async {
    return const ZReportPrintResult(
      succeeded: false,
      message: 'Bu cihazda yapılandırılmış bir ESC/POS yazıcı bağlantısı yok. '
          'Rapor içeriği önizlemede görüntüleniyor.',
    );
  }
}

/// `Platform.isWindows ? WindowsZReportPrinterAdapter : Unconfigured...` —
/// same fail-closed-off-Windows shape as `rawPrinterAdapterProvider`.
ZReportPrinterAdapter resolveZReportPrinterAdapter({
  required RawPrinterAdapter rawPrinterAdapter,
  required String printerName,
}) {
  return Platform.isWindows
      ? WindowsZReportPrinterAdapter(
          rawPrinterAdapter: rawPrinterAdapter,
          printerName: printerName,
        )
      : const UnconfiguredZReportPrinterAdapter();
}
