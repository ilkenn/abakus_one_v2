import '../receipts/receipt_print_result.dart';
import 'kitchen_ticket.dart';

/// Sends a [KitchenTicket] to a physical/virtual kitchen printer —
/// foundation only, no real printer integration exists this sprint.
/// Mirrors `ReceiptPrintProvider`'s exact shape (`docs/decisions.md`
/// ADR-013): a ticket's content model is different from a receipt's, but
/// the "print this document" contract is the same shape, so it's reused,
/// not reinvented.
abstract interface class KitchenTicketPrintProvider {
  Future<ReceiptPrintResult> print(KitchenTicket ticket);
}

/// The only implementation this sprint — always reports "unavailable",
/// same honest-default pattern as `NoOpReceiptPrintProvider`: printing has
/// no security consequence if it's absent, unlike authorization.
class NoOpKitchenTicketPrintProvider implements KitchenTicketPrintProvider {
  const NoOpKitchenTicketPrintProvider();

  @override
  Future<ReceiptPrintResult> print(KitchenTicket ticket) async {
    return const ReceiptPrintResult(
      status: ReceiptPrintResultStatus.unavailable,
      errorMessage: 'Mutfak yazıcısı entegrasyonu henüz yapılandırılmadı.',
    );
  }
}
