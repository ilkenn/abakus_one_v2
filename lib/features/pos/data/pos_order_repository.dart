import '../../orders/domain/models/order.dart';
import '../domain/models/pos_order_session.dart';

/// Persistence boundary for POS drafts and submitted orders.
///
/// **No backend implementation this sprint** — `InMemoryPosOrderRepository`
/// is the only implementation, for tests and local development. A future
/// Firebase-backed implementation replaces it behind this same interface;
/// nothing that depends on [PosOrderRepository] needs to change when that
/// happens (mirrors `OrdersRepository`/`LocalOrdersRepository`'s existing
/// pattern in this codebase).
///
/// [saveDraft]/[getDraft]/[deleteDraft] are keyed by a caller-supplied
/// `draftId` — this repository never generates one itself (mirrors
/// `OrderId`/`OrderNumber`'s externally-supplied-identity convention). In
/// practice the caller always passes `PosOrderSession.sessionId` as the
/// draft key — a session and its draft share one identity.
abstract interface class PosOrderRepository {
  Future<void> saveDraft(String draftId, PosOrderSession session);

  /// `null` if no draft is stored under [draftId].
  Future<PosOrderSession?> getDraft(String draftId);

  Future<void> deleteDraft(String draftId);

  /// Persists an already-built, already-transitioned [order] (produced by
  /// `SubmitPosOrder`) and returns it back — this method does not
  /// construct or transition an [Order] itself, only stores one.
  Future<Order> submitOrder(Order order);
}

/// In-memory [PosOrderRepository] — the only implementation this sprint.
/// Storing a [PosOrderSession]/[Order] reference directly is safe without
/// an extra defensive copy: both types are already immutable (see
/// [PosOrderSession]'s own doc comment on why its constructor defensively
/// copies [PosOrderSession.lines]) — there is no mutable state here for a
/// caller to reach back into after the fact.
class InMemoryPosOrderRepository implements PosOrderRepository {
  final Map<String, PosOrderSession> _drafts = {};
  final Map<String, Order> _submittedOrders = {};

  /// Test-only failure injection — when set, the **next** call to the
  /// matching method throws [Exception] instead of succeeding, then the
  /// injected failure is cleared automatically (one-shot). This is what
  /// makes a "submit fails once, then a retry succeeds" test possible
  /// without manual reset boilerplate.
  Exception? failOnSaveDraft;
  Exception? failOnGetDraft;
  Exception? failOnDeleteDraft;
  Exception? failOnSubmitOrder;

  @override
  Future<void> saveDraft(String draftId, PosOrderSession session) async {
    final failure = failOnSaveDraft;
    if (failure != null) {
      failOnSaveDraft = null;
      throw failure;
    }
    _drafts[draftId] = session;
  }

  @override
  Future<PosOrderSession?> getDraft(String draftId) async {
    final failure = failOnGetDraft;
    if (failure != null) {
      failOnGetDraft = null;
      throw failure;
    }
    return _drafts[draftId];
  }

  @override
  Future<void> deleteDraft(String draftId) async {
    final failure = failOnDeleteDraft;
    if (failure != null) {
      failOnDeleteDraft = null;
      throw failure;
    }
    _drafts.remove(draftId);
  }

  @override
  Future<Order> submitOrder(Order order) async {
    final failure = failOnSubmitOrder;
    if (failure != null) {
      failOnSubmitOrder = null;
      throw failure;
    }
    _submittedOrders[order.id.value] = order;
    return order;
  }

  /// Test/diagnostic access to what's actually been persisted — not part
  /// of the [PosOrderRepository] interface itself.
  List<Order> get submittedOrders => List.unmodifiable(_submittedOrders.values);
  List<String> get draftIds => List.unmodifiable(_drafts.keys);
}
