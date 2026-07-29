import '../../../../core/utils/clock.dart';
import '../../data/kitchen_print_attempt_repository.dart';
import '../../domain/kds/kitchen_print_attempt.dart';
import '../../domain/kitchen/kitchen_ticket.dart';
import '../../domain/kitchen/kitchen_ticket_print_provider.dart';
import '../../domain/receipts/receipt_print_result.dart';
import '../identity/kitchen_print_attempt_id_generator.dart';

/// Prints a [KitchenTicket] via a primary provider, retrying once through
/// an optional fallback provider if the primary attempt is
/// [ReceiptPrintResultStatus.failed]/[ReceiptPrintResultStatus.unavailable]
/// — Phase 4I's "retry contract"/"fallback printer contract." Every
/// attempt (primary and fallback alike) is recorded via
/// [KitchenPrintAttemptRepository], regardless of outcome.
///
/// **Printing is never the authoritative source of kitchen state**: this
/// use case only records what happened and returns the final result — it
/// never touches `KitchenTicketRepository`/`KitchenProjectionRepository`,
/// and a total failure (primary and fallback both fail) still leaves
/// every `KitchenEvent`/`KitchenWorkItem` the ticket already produced
/// completely intact.
class PrintKitchenTicketWithRetry {
  const PrintKitchenTicketWithRetry({
    required Clock clock,
    required KitchenPrintAttemptIdGenerator idGenerator,
    required KitchenPrintAttemptRepository attemptRepository,
    required KitchenTicketPrintProvider primaryProvider,
    KitchenTicketPrintProvider? fallbackProvider,
  })  : _clock = clock,
        _idGenerator = idGenerator,
        _attemptRepository = attemptRepository,
        _primaryProvider = primaryProvider,
        _fallbackProvider = fallbackProvider;

  final Clock _clock;
  final KitchenPrintAttemptIdGenerator _idGenerator;
  final KitchenPrintAttemptRepository _attemptRepository;
  final KitchenTicketPrintProvider _primaryProvider;
  final KitchenTicketPrintProvider? _fallbackProvider;

  Future<ReceiptPrintResult> call(KitchenTicket ticket) async {
    final primaryResult = await _primaryProvider.print(ticket);
    await _record(
      ticket: ticket,
      providerLabel: 'primary',
      result: primaryResult,
      isRetry: false,
      isFallback: false,
    );
    if (primaryResult.status == ReceiptPrintResultStatus.success) {
      return primaryResult;
    }

    final fallback = _fallbackProvider;
    if (fallback == null) return primaryResult;

    final fallbackResult = await fallback.print(ticket);
    await _record(
      ticket: ticket,
      providerLabel: 'fallback',
      result: fallbackResult,
      isRetry: true,
      isFallback: true,
    );
    return fallbackResult;
  }

  Future<void> _record({
    required KitchenTicket ticket,
    required String providerLabel,
    required ReceiptPrintResult result,
    required bool isRetry,
    required bool isFallback,
  }) async {
    await _attemptRepository.append(KitchenPrintAttempt(
      id: _idGenerator.nextAttemptId(),
      kitchenTicketId: ticket.id,
      providerLabel: providerLabel,
      result: result.status,
      errorMessage: result.errorMessage,
      isRetry: isRetry,
      isFallback: isFallback,
      attemptedAt: _clock.now(),
    ));
  }
}
