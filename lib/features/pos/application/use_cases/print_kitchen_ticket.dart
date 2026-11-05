import 'dart:typed_data';

import '../../../printing/data/windows_raw_printer_adapter.dart';
import '../../../printing/domain/esc_pos_kitchen_ticket_encoder.dart';
import '../../domain/kitchen/kitchen_ticket.dart';

/// Encodes an already-built [KitchenTicket] to ESC/POS bytes and sends it
/// to the configured Windows printer — Self-Order QR Faz 5 (23-rule plan
/// §6, "onay sonrası mutfak yazdırma"). Mirrors `PrintTableReceipt`'s own
/// shape, simpler: the ticket is already built by the caller (from the
/// just-accepted `Order`, via `KitchenTicketMapper.fromOrder`), there is
/// nothing left for this class to fetch.
class PrintKitchenTicket {
  const PrintKitchenTicket({required this.rawPrinterAdapter});

  final RawPrinterAdapter rawPrinterAdapter;

  Future<void> call({
    required KitchenTicket ticket,
    required String printerName,
  }) async {
    final Uint8List bytes = EscPosKitchenTicketEncoder.encode(ticket);
    await rawPrinterAdapter.printRaw(
      printerName: printerName,
      bytes: bytes,
      jobName: 'Mutfak Fişi - ${ticket.header.orderNumber}',
    );
  }
}
