import '../../orders/domain/models/order_id.dart';
import '../domain/models/order_closure.dart';

/// Persistence boundary for [OrderClosure] records.
///
/// **Append-only** (`docs/decisions.md` ADR-012) — same shape and
/// rationale as `PaymentSessionRepository`: [save] never overwrites a
/// previous revision, and lookups always resolve to the highest-revision
/// entry for their target, while the full history remains queryable.
abstract interface class OrderClosureRepository {
  /// Appends [closure] as a new revision. Never overwrites an earlier
  /// revision of the same `OrderClosure.closureId`.
  Future<void> save(OrderClosure closure);

  /// The latest revision of the closure record with this exact id, or
  /// `null` if none has ever been saved.
  Future<OrderClosure?> findByClosureId(String closureId);

  /// The latest revision of the (single, ongoing) closure record for
  /// [orderId] — an order has exactly one [OrderClosure] across its
  /// entire lifecycle (unlike `PaymentSession`, which an order may have
  /// several of over time). `null` if none exists yet.
  Future<OrderClosure?> findCurrentByOrderId(OrderId orderId);

  /// Every revision ever saved for [orderId]'s closure record, oldest
  /// first — the full open/close/reopen/reclose history.
  Future<List<OrderClosure>> findHistoryByOrderId(OrderId orderId);
}

/// In-memory [OrderClosureRepository] — the only implementation this
/// sprint. Keeps every revision ever saved, satisfying append-only
/// structurally.
class InMemoryOrderClosureRepository implements OrderClosureRepository {
  final List<OrderClosure> _allRevisions = [];

  /// Test-only failure injection — one-shot, mirrors
  /// `InMemoryPaymentSessionRepository`'s existing pattern.
  Exception? failOnSave;

  @override
  Future<void> save(OrderClosure closure) async {
    final failure = failOnSave;
    if (failure != null) {
      failOnSave = null;
      throw failure;
    }
    _allRevisions.add(closure);
  }

  @override
  Future<OrderClosure?> findByClosureId(String closureId) async {
    return _latestRevisionOf(
      _allRevisions.where((c) => c.closureId == closureId),
    );
  }

  @override
  Future<OrderClosure?> findCurrentByOrderId(OrderId orderId) async {
    return _latestRevisionOf(
      _allRevisions.where((c) => c.orderId == orderId),
    );
  }

  @override
  Future<List<OrderClosure>> findHistoryByOrderId(OrderId orderId) async {
    final forOrder = _allRevisions.where((c) => c.orderId == orderId).toList()
      ..sort((a, b) => a.revision.compareTo(b.revision));
    return List.unmodifiable(forOrder);
  }

  OrderClosure? _latestRevisionOf(Iterable<OrderClosure> revisions) {
    OrderClosure? latest;
    for (final closure in revisions) {
      if (latest == null || closure.revision > latest.revision) {
        latest = closure;
      }
    }
    return latest;
  }

  /// Test/diagnostic access — not part of [OrderClosureRepository].
  List<OrderClosure> get allRevisions => List.unmodifiable(_allRevisions);
}
