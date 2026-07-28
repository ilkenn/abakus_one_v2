import '../domain/models/table_session.dart';

/// Storage for [TableSession] records — mutable (a session's own fields
/// evolve via `copyWith`/`withGuestAdded`/`withOrderAdded`/`withCheckAdded`
/// as the visit progresses; unlike a financial/audit record, only the
/// session's current shape matters here, not a revision history of it).
///
/// The first real persistence for `TableSession` — the table-QR
/// architecture phase (`docs/table_qr_architecture.md`) defined the model
/// but explicitly deferred session-orchestration/persistence; this is that
/// orchestration's storage seam (Phase 3 Sprint 3D).
abstract interface class TableSessionRepository {
  Future<void> save(TableSession session);

  Future<TableSession?> findById(String sessionId);

  /// The currently open/pending session for [tableId], if any — a table
  /// has at most one active session at a time (a new QR scan/staff seating
  /// action after close always starts a new session, per
  /// `docs/table_qr_architecture.md` §7's isolation rule).
  Future<TableSession?> findActiveByTableId(String tableId);
}

/// In-memory [TableSessionRepository] — the only implementation this
/// sprint.
class InMemoryTableSessionRepository implements TableSessionRepository {
  final Map<String, TableSession> _sessionsById = {};

  @override
  Future<void> save(TableSession session) async {
    _sessionsById[session.id] = session;
  }

  @override
  Future<TableSession?> findById(String sessionId) async {
    return _sessionsById[sessionId];
  }

  @override
  Future<TableSession?> findActiveByTableId(String tableId) async {
    for (final session in _sessionsById.values) {
      if (session.tableId == tableId && session.isOpen) return session;
    }
    return null;
  }
}
