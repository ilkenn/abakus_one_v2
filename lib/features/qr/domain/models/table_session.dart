/// Lifecycle status of a [TableSession].
enum TableSessionStatus { pending, active, closed, cancelled }

/// Represents one active customer visit at a physical table, from the first
/// successful QR scan until the table is cleared for the next visit.
///
/// A session intentionally holds lists of guest session ids and order ids
/// rather than single values: a table visit already, structurally, may
/// involve multiple guests and multiple orders. Table transfer, table
/// merge, and split-bill are explicitly out of scope for this phase — see
/// `docs/table_qr_architecture.md` — and are not modeled here to avoid
/// speculative fields with no current caller.
///
/// [checkIds] is a Phase 3 Sprint 3D addition: the adisyon/check(s) opened
/// under this table visit (`lib/features/pos/domain/models/check.dart`).
/// `activeOrderIds` remains what it already was (populated once a check is
/// actually submitted into an `Order`) — `checkIds` is the superset that
/// also includes still-open, not-yet-submitted checks.
class TableSession {
  final String id;
  final String restaurantId;
  final String branchId;
  final String tableId;
  final TableSessionStatus status;
  final DateTime openedAt;
  final DateTime? closedAt;
  final List<String> guestSessionIds;
  final List<String> activeOrderIds;
  final List<String> checkIds;

  const TableSession({
    required this.id,
    required this.restaurantId,
    required this.branchId,
    required this.tableId,
    required this.status,
    required this.openedAt,
    this.closedAt,
    required this.guestSessionIds,
    required this.activeOrderIds,
    this.checkIds = const [],
  });

  /// Whether the session currently represents a live table visit (as
  /// opposed to one that has been closed or cancelled).
  bool get isOpen =>
      status == TableSessionStatus.pending ||
      status == TableSessionStatus.active;

  /// Whether the session can currently accept a new guest joining the
  /// table.
  bool get canAcceptNewGuest => status == TableSessionStatus.active;

  TableSession withGuestAdded(String guestSessionId) {
    if (guestSessionIds.contains(guestSessionId)) return this;
    return copyWith(
      guestSessionIds: [...guestSessionIds, guestSessionId],
    );
  }

  TableSession withOrderAdded(String orderId) {
    if (activeOrderIds.contains(orderId)) return this;
    return copyWith(activeOrderIds: [...activeOrderIds, orderId]);
  }

  TableSession withCheckAdded(String checkId) {
    if (checkIds.contains(checkId)) return this;
    return copyWith(checkIds: [...checkIds, checkId]);
  }

  /// Removes [checkId] — used by `TransferCheck` (Phase 3 Sprint 3D) when
  /// moving a check from this session to a different table's session. A
  /// no-op if [checkId] isn't present.
  TableSession withCheckRemoved(String checkId) {
    if (!checkIds.contains(checkId)) return this;
    return copyWith(checkIds: checkIds.where((id) => id != checkId).toList());
  }

  TableSession closed({required DateTime at}) {
    return copyWith(status: TableSessionStatus.closed, closedAt: at);
  }

  TableSession cancelled({required DateTime at}) {
    return copyWith(status: TableSessionStatus.cancelled, closedAt: at);
  }

  TableSession copyWith({
    String? id,
    String? restaurantId,
    String? branchId,
    String? tableId,
    TableSessionStatus? status,
    DateTime? openedAt,
    DateTime? closedAt,
    List<String>? guestSessionIds,
    List<String>? activeOrderIds,
    List<String>? checkIds,
  }) {
    return TableSession(
      id: id ?? this.id,
      restaurantId: restaurantId ?? this.restaurantId,
      branchId: branchId ?? this.branchId,
      tableId: tableId ?? this.tableId,
      status: status ?? this.status,
      openedAt: openedAt ?? this.openedAt,
      closedAt: closedAt ?? this.closedAt,
      guestSessionIds: guestSessionIds ?? this.guestSessionIds,
      activeOrderIds: activeOrderIds ?? this.activeOrderIds,
      checkIds: checkIds ?? this.checkIds,
    );
  }
}
