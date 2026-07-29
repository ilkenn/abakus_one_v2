import '../domain/kds/kitchen_print_attempt.dart';

/// Append-only storage for [KitchenPrintAttempt] — no update or delete
/// method exists at all. A failed print attempt is never erased; a retry
/// is always a new record.
abstract interface class KitchenPrintAttemptRepository {
  Future<void> append(KitchenPrintAttempt attempt);

  /// Every attempt for [kitchenTicketId], oldest first.
  Future<List<KitchenPrintAttempt>> findByTicketId(String kitchenTicketId);
}

/// In-memory [KitchenPrintAttemptRepository] — the only implementation
/// this phase.
class InMemoryKitchenPrintAttemptRepository
    implements KitchenPrintAttemptRepository {
  final List<KitchenPrintAttempt> _attempts = [];

  @override
  Future<void> append(KitchenPrintAttempt attempt) async {
    _attempts.add(attempt);
  }

  @override
  Future<List<KitchenPrintAttempt>> findByTicketId(
      String kitchenTicketId) async {
    return List.unmodifiable(
      _attempts.where((a) => a.kitchenTicketId == kitchenTicketId),
    );
  }
}
