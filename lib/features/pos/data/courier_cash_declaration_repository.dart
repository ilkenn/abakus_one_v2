import '../domain/courier_settlement/courier_cash_declaration.dart';

/// Append-only storage for [CourierCashDeclaration]s — **never
/// overwritten**; a redeclaration is always a new record. No update
/// method exists at all, mirroring `CashCountRepository`.
abstract interface class CourierCashDeclarationRepository {
  Future<void> append(CourierCashDeclaration declaration);

  Future<CourierCashDeclaration?> findById(String declarationId);

  /// Every declaration ever submitted for [settlementSessionId], oldest
  /// first.
  Future<List<CourierCashDeclaration>> findBySettlementSessionId(
      String settlementSessionId);

  /// The most recently submitted declaration for [settlementSessionId],
  /// or `null` if none yet.
  Future<CourierCashDeclaration?> findLatestBySettlementSessionId(
      String settlementSessionId);
}

/// In-memory [CourierCashDeclarationRepository] — the only implementation
/// this sprint.
class InMemoryCourierCashDeclarationRepository
    implements CourierCashDeclarationRepository {
  final List<CourierCashDeclaration> _declarations = [];

  @override
  Future<void> append(CourierCashDeclaration declaration) async {
    _declarations.add(declaration);
  }

  @override
  Future<CourierCashDeclaration?> findById(String declarationId) async {
    for (final declaration in _declarations) {
      if (declaration.id == declarationId) return declaration;
    }
    return null;
  }

  @override
  Future<List<CourierCashDeclaration>> findBySettlementSessionId(
      String settlementSessionId) async {
    return List.unmodifiable(
      _declarations.where((d) => d.settlementSessionId == settlementSessionId),
    );
  }

  @override
  Future<CourierCashDeclaration?> findLatestBySettlementSessionId(
      String settlementSessionId) async {
    final matches = _declarations
        .where((d) => d.settlementSessionId == settlementSessionId)
        .toList();
    if (matches.isEmpty) return null;
    return matches.last;
  }
}
