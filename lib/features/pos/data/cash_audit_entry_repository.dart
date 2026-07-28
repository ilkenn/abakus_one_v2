import '../domain/cash/cash_audit_entry.dart';

/// Append-only storage for [CashAuditEntry] events, keyed by the drawer
/// they concern. **No update or delete method exists at all** — mirrors
/// `ClosureAuditEntryRepository`/`RestaurantOperationsAuditEntryRepository`'s
/// structurally-append-only interface shape exactly.
abstract interface class CashAuditEntryRepository {
  Future<void> appendEvent(CashAuditEntry entry);

  /// Every event ever appended for [drawerId], oldest first.
  Future<List<CashAuditEntry>> findByDrawerId(String drawerId);

  /// Every event ever appended for [sessionId], oldest first.
  Future<List<CashAuditEntry>> findBySessionId(String sessionId);
}

/// In-memory [CashAuditEntryRepository] — the only implementation this
/// sprint.
class InMemoryCashAuditEntryRepository implements CashAuditEntryRepository {
  final List<CashAuditEntry> _entries = [];

  @override
  Future<void> appendEvent(CashAuditEntry entry) async {
    _entries.add(entry);
  }

  @override
  Future<List<CashAuditEntry>> findByDrawerId(String drawerId) async {
    return List.unmodifiable(
      _entries.where((entry) => entry.drawerId == drawerId),
    );
  }

  @override
  Future<List<CashAuditEntry>> findBySessionId(String sessionId) async {
    return List.unmodifiable(
      _entries.where((entry) => entry.sessionId == sessionId),
    );
  }
}
