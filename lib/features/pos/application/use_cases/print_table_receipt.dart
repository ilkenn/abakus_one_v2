import 'dart:typed_data';

import '../../../printing/data/windows_raw_printer_adapter.dart';
import '../../../printing/domain/esc_pos_receipt_encoder.dart';
import '../../../printing/domain/receipt_codepage.dart';
import '../../data/pos_action_gateway.dart' show PosDeviceContext;
import '../../data/pos_operational_view_gateway.dart';
import '../../domain/receipts/table_receipt_builder.dart';

/// The one real "Yazdır" action behind all three trigger points the
/// 2026-11-05 printer integration wires up (the Masalar grid's quick
/// button, the table workspace's quick-action bar, and the "... Diğer"
/// grid tile) — fetches the table's current operational view fresh (the
/// grid's lightweight overview and even the workspace's already-loaded
/// view can be a poll cycle stale; a till receipt must reflect what's
/// actually on the check right now), builds the receipt content, encodes
/// it to ESC/POS bytes, and sends it to the configured Windows printer.
class PrintTableReceipt {
  const PrintTableReceipt({
    required this.operationalViewGateway,
    required this.rawPrinterAdapter,
  });

  final PosOperationalViewGateway operationalViewGateway;
  final RawPrinterAdapter rawPrinterAdapter;

  Future<void> call({
    required PosDeviceContext ctx,
    required String tableId,
    // `null` lets the Masalar grid's quick button (which doesn't have a
    // checkId in hand yet, unlike the workspace's own trigger points) print
    // straight from the card — this resolves the table's own currently
    // open/ready-for-payment check instead.
    required String? checkId,
    required String tableName,
    required String branchName,
    required String printerName,
    required String Function(String productId) recipeFor,
    ReceiptCodepage codepage = ReceiptCodepage.wpc1254,
  }) async {
    final view = await operationalViewGateway.getTableView(
      organizationId: ctx.organizationId,
      branchId: ctx.branchId,
      tableId: tableId,
      deviceId: ctx.deviceId,
      deviceSessionId: ctx.deviceSessionId,
    );

    final resolvedCheckId = checkId ?? _resolveOpenCheckId(view);
    if (resolvedCheckId == null) {
      throw const PosOperationalViewException(
        'no-open-check',
        'Bu masada açık bir hesap yok.',
      );
    }

    final receiptNumber = resolvedCheckId.length > 8
        ? resolvedCheckId.substring(0, 8).toUpperCase()
        : resolvedCheckId;

    final document = TableReceiptBuilder.build(
      view: view,
      checkId: resolvedCheckId,
      restaurantName: 'Abaküs',
      branchName: branchName,
      tableName: tableName,
      receiptNumber: receiptNumber,
      issuedAt: DateTime.now(),
      recipeFor: recipeFor,
    );

    final Uint8List bytes =
        EscPosReceiptEncoder.encode(document, codepage: codepage);

    await rawPrinterAdapter.printRaw(
      printerName: printerName,
      bytes: bytes,
      jobName: 'Adisyon - $tableName',
    );
  }

  /// Prefers `readyForPayment` (staff already asked for the bill) over
  /// `open`, then falls back to the first `open` check — `paid`/
  /// `cancelled` checks are never a valid print target.
  String? _resolveOpenCheckId(PosTableOperationalView view) {
    final readyForPayment = view.checks
        .where((c) => c['status'] == 'readyForPayment')
        .map((c) => c['id'] as String?)
        .whereType<String>();
    if (readyForPayment.isNotEmpty) return readyForPayment.first;

    final open = view.checks
        .where((c) => c['status'] == 'open')
        .map((c) => c['id'] as String?)
        .whereType<String>();
    return open.isNotEmpty ? open.first : null;
  }
}
