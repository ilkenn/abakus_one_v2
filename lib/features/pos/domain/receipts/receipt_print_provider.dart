import '../../../orders/domain/receipt/receipt.dart';
import 'receipt_print_result.dart';

/// Sends a [Receipt] to a physical/virtual printer — foundation only, no
/// real printer integration exists this sprint
/// (`docs/decisions.md` ADR-012's duplicate-receipt-foundation note).
abstract interface class ReceiptPrintProvider {
  Future<ReceiptPrintResult> print(Receipt receipt);
}

/// The only implementation this sprint — always reports "unavailable",
/// same honesty pattern as `UnavailableExchangeRateProvider`: a safe
/// default that never claims to have printed something it didn't (unlike
/// `PosAuthorizationPolicy`, which has no default at all — printing a
/// receipt has no security consequence if it silently "succeeds" as a
/// no-op the way granting an authorization would, so an honest
/// always-unavailable default is the right shape here, not an absent one).
class NoOpReceiptPrintProvider implements ReceiptPrintProvider {
  const NoOpReceiptPrintProvider();

  @override
  Future<ReceiptPrintResult> print(Receipt receipt) async {
    return const ReceiptPrintResult(
      status: ReceiptPrintResultStatus.unavailable,
      errorMessage: 'Yazıcı entegrasyonu henüz yapılandırılmadı.',
    );
  }
}
