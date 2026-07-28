import '../../orders/domain/models/order_id.dart';
import '../domain/models/payment_session.dart';
import '../domain/models/payment_session_status.dart';

/// Persistence boundary for [PaymentSession]s.
///
/// **Append-only** (`docs/decisions.md` ADR-012): [save] never overwrites
/// a previously stored revision — every call adds a new entry, and
/// [findBySessionId]/[findActiveByOrderId] always resolve to the
/// *highest-revision* entry for their target. A `PaymentSession`'s full
/// revision history remains queryable via [findHistoryByOrderId] even
/// after it's superseded — nothing is ever deleted or mutated in place.
///
/// **No backend implementation this sprint** — `InMemoryPaymentSessionRepository`
/// is the only implementation, mirroring `PosOrderRepository`'s existing
/// in-memory-only pattern.
abstract interface class PaymentSessionRepository {
  /// Appends [session] as a new revision. Never overwrites an earlier
  /// revision of the same `PaymentSession.id`.
  Future<void> save(PaymentSession session);

  /// The latest known revision of the session with this exact id, or
  /// `null` if none has ever been saved.
  Future<PaymentSession?> findBySessionId(String sessionId);

  /// The most recently started session for [orderId], if its latest
  /// revision is still in a non-terminal `PaymentSessionStatus`
  /// (`collecting`/`readyToComplete`/`completing`/`failed`). `null` if no
  /// session exists for this order, or the most recent one has already
  /// reached `completed`/`cancelled`.
  Future<PaymentSession?> findActiveByOrderId(OrderId orderId);

  /// Every revision of every session ever saved for [orderId], oldest
  /// first — the full payment history for that order, regardless of how
  /// many separate sessions (e.g. after a cancel-and-restart) it went
  /// through.
  Future<List<PaymentSession>> findHistoryByOrderId(OrderId orderId);
}

/// In-memory [PaymentSessionRepository] — the only implementation this
/// sprint. Keeps every revision ever saved, never overwrites or removes
/// one, satisfying the append-only requirement structurally rather than by
/// convention alone.
class InMemoryPaymentSessionRepository implements PaymentSessionRepository {
  final List<PaymentSession> _allRevisions = [];

  /// Test-only failure injection — one-shot, mirrors
  /// `InMemoryPosOrderRepository`'s existing pattern.
  Exception? failOnSave;

  @override
  Future<void> save(PaymentSession session) async {
    final failure = failOnSave;
    if (failure != null) {
      failOnSave = null;
      throw failure;
    }
    _allRevisions.add(session);
  }

  @override
  Future<PaymentSession?> findBySessionId(String sessionId) async {
    return _latestRevisionOf(
      _allRevisions.where((s) => s.id == sessionId),
    );
  }

  @override
  Future<PaymentSession?> findActiveByOrderId(OrderId orderId) async {
    final forOrder = _allRevisions.where((s) => s.orderId == orderId);
    if (forOrder.isEmpty) return null;

    final sessionIds = forOrder.map((s) => s.id).toSet();
    PaymentSession? mostRecentlyStarted;
    for (final id in sessionIds) {
      final latestForId = _latestRevisionOf(forOrder.where((s) => s.id == id))!;
      if (mostRecentlyStarted == null ||
          latestForId.createdAt.isAfter(mostRecentlyStarted.createdAt)) {
        mostRecentlyStarted = latestForId;
      }
    }

    if (mostRecentlyStarted == null) return null;
    final isTerminal =
        mostRecentlyStarted.status == PaymentSessionStatus.completed ||
            mostRecentlyStarted.status == PaymentSessionStatus.cancelled;
    return isTerminal ? null : mostRecentlyStarted;
  }

  @override
  Future<List<PaymentSession>> findHistoryByOrderId(OrderId orderId) async {
    final forOrder = _allRevisions.where((s) => s.orderId == orderId).toList()
      ..sort((a, b) {
        final byCreated = a.createdAt.compareTo(b.createdAt);
        return byCreated != 0 ? byCreated : a.revision.compareTo(b.revision);
      });
    return List.unmodifiable(forOrder);
  }

  PaymentSession? _latestRevisionOf(Iterable<PaymentSession> revisions) {
    PaymentSession? latest;
    for (final session in revisions) {
      if (latest == null || session.revision > latest.revision) {
        latest = session;
      }
    }
    return latest;
  }

  /// Test/diagnostic access — not part of [PaymentSessionRepository].
  List<PaymentSession> get allRevisions => List.unmodifiable(_allRevisions);
}
