import '../receipts/receipt_print_result.dart';

/// One immutable, append-only record of a single print attempt for a
/// `KitchenTicket` — Phase 4I's "print-attempt history." Printing itself
/// (`KitchenTicketPrintProvider`) has never persisted its own outcome
/// anywhere (Phase 3 Sprint 3D); this is purely additive tracking layered
/// on top, never a replacement for the ticket itself, which remains
/// authoritative regardless of print outcome.
class KitchenPrintAttempt {
  const KitchenPrintAttempt({
    required this.id,
    required this.kitchenTicketId,
    required this.providerLabel,
    required this.result,
    this.errorMessage,
    required this.isRetry,
    this.isFallback = false,
    required this.attemptedAt,
  });

  final String id;
  final String kitchenTicketId;

  /// A human-readable label for which provider made this attempt (e.g.
  /// `'primary'`/`'fallback'`) — providers themselves carry no id/name of
  /// their own (`KitchenTicketPrintProvider` is a bare `print()` contract).
  final String providerLabel;

  final ReceiptPrintResultStatus result;
  final String? errorMessage;

  /// `true` if this attempt followed an earlier failed/unavailable one for
  /// the same ticket.
  final bool isRetry;

  /// `true` if this attempt used the fallback provider rather than the
  /// primary one.
  final bool isFallback;

  final DateTime attemptedAt;
}
