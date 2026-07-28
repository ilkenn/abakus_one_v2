import '../../../orders/domain/models/order_id.dart';
import 'check_status.dart';

/// One adisyon/check within a [TableSession] — the coordination record
/// between a table visit and this codebase's existing, unchanged POS
/// payment pipeline.
///
/// **Deliberately thin.** A `Check` never duplicates `PosOrderSession`,
/// `Order`, `OrderClosure`, or `PaymentSession` — it only tracks *which*
/// session/order belongs to this check, within this table visit:
///
/// ```text
/// Check --(pre-submission)--> owns one PosOrderSession (posOrderSessionId)
/// Check --(post-submission)-> becomes one Order (orderId), whose own
///                              OrderClosure/PaymentSession lineage is
///                              untouched by this sprint (see ADR-013).
/// ```
///
/// Whether a check is "resolved" enough for `CloseTableSession` to allow
/// the table session to close is decided by that use case, not by this
/// class — a `cancelled` check needs nothing further, while a `submitted`
/// check is resolved only once its own `Order`'s `OrderClosure` reaches
/// `closed`, which lives in a different repository and is never duplicated
/// onto `Check` itself.
///
/// **Append-only**: never mutated in place — every change produces a new
/// instance with the same [id] and an incremented [revision];
/// `CheckRepository.save` always appends.
class Check {
  const Check({
    required this.id,
    required this.tableSessionId,
    required this.branchId,
    this.guestSessionIds = const [],
    required this.status,
    this.posOrderSessionId,
    this.orderId,
    required this.openedAt,
    this.closedAt,
    required this.revision,
  });

  /// Stable across every revision — what [CheckRepository] queries by.
  final String id;

  final String tableSessionId;
  final String branchId;
  final List<String> guestSessionIds;

  final CheckStatus status;

  /// Set once, at [OpenCheck] time — the in-progress cashier session this
  /// check is being edited through. Remains set even after submission (for
  /// traceability); [orderId] is what matters once `status ==
  /// CheckStatus.submitted`.
  final String? posOrderSessionId;

  /// `null` until `SubmitCheck` runs; non-null exactly when
  /// `status == CheckStatus.submitted`.
  final OrderId? orderId;

  final DateTime openedAt;
  final DateTime? closedAt;

  /// Optimistic-concurrency counter — starts at 1.
  final int revision;

  /// Appends [guestSessionId] if not already present (idempotent, mirrors
  /// `TableSession.withGuestAdded`) and bumps [revision].
  Check withGuestAdded(String guestSessionId) {
    if (guestSessionIds.contains(guestSessionId)) return this;
    return copyWith(
      guestSessionIds: [...guestSessionIds, guestSessionId],
      revision: revision + 1,
    );
  }

  Check copyWith({
    String? tableSessionId,
    List<String>? guestSessionIds,
    CheckStatus? status,
    String? posOrderSessionId,
    OrderId? orderId,
    DateTime? closedAt,
    int? revision,
  }) {
    return Check(
      id: id,
      tableSessionId: tableSessionId ?? this.tableSessionId,
      branchId: branchId,
      guestSessionIds: guestSessionIds ?? this.guestSessionIds,
      status: status ?? this.status,
      posOrderSessionId: posOrderSessionId ?? this.posOrderSessionId,
      orderId: orderId ?? this.orderId,
      openedAt: openedAt,
      closedAt: closedAt ?? this.closedAt,
      revision: revision ?? this.revision,
    );
  }
}
