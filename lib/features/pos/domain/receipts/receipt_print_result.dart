enum ReceiptPrintResultStatus { success, unavailable, failed }

/// The outcome of a [ReceiptPrintProvider] call.
class ReceiptPrintResult {
  const ReceiptPrintResult({required this.status, this.errorMessage});

  final ReceiptPrintResultStatus status;
  final String? errorMessage;
}
