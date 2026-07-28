import '../domain/cash/cash_movement.dart';

/// Append-only storage for [CashMovement]s — no update or delete method
/// exists (movements are immutable and never removed; reversing one means
/// recording a new, offsetting movement — see `ReverseCashMovement`).
abstract interface class CashMovementRepository {
  Future<void> append(CashMovement movement);

  Future<CashMovement?> findById(String movementId);

  /// Every movement recorded for [sessionId], oldest first.
  Future<List<CashMovement>> findBySessionId(String sessionId);
}

/// In-memory [CashMovementRepository] — the only implementation this
/// sprint.
class InMemoryCashMovementRepository implements CashMovementRepository {
  final List<CashMovement> _movements = [];

  @override
  Future<void> append(CashMovement movement) async {
    _movements.add(movement);
  }

  @override
  Future<CashMovement?> findById(String movementId) async {
    for (final movement in _movements) {
      if (movement.id == movementId) return movement;
    }
    return null;
  }

  @override
  Future<List<CashMovement>> findBySessionId(String sessionId) async {
    return List.unmodifiable(
      _movements.where((movement) => movement.sessionId == sessionId),
    );
  }
}
