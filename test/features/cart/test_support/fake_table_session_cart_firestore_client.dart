import 'dart:async';

import 'package:abakus_one_v2/features/cart/data/table_session_cart_firestore_client.dart';
import 'package:abakus_one_v2/features/cart/domain/models/cart_item.dart';

/// An in-memory stand-in for [DefaultTableSessionCartFirestoreClient] — any
/// widget/screen test that pumps a dine-in-QR screen with an active table
/// context needs this override (never the real default, which touches
/// `FirebaseFirestore.instance` and has no app to attach to in a test).
///
/// Mirrors the real Firestore client's own semantics closely enough for
/// tests: [watchLines] emits the current snapshot to every new subscriber
/// immediately (like a real `.snapshots()` listener always does on
/// subscribe), then again on every subsequent mutation.
class FakeTableSessionCartFirestoreClient
    implements TableSessionCartFirestoreClient {
  final Map<String, Map<String, CartItem>> _linesByTableSession = {};
  final Map<String, StreamController<List<CartItem>>> _controllers = {};

  StreamController<List<CartItem>> _controllerFor(String tableSessionId) {
    return _controllers.putIfAbsent(
      tableSessionId,
      () => StreamController<List<CartItem>>.broadcast(),
    );
  }

  void _emitCurrent(String tableSessionId) {
    final lines = _linesByTableSession[tableSessionId]?.values.toList() ??
        const <CartItem>[];
    _controllerFor(tableSessionId).add(lines);
  }

  @override
  Stream<List<CartItem>> watchLines(String tableSessionId) {
    final controller = _controllerFor(tableSessionId);
    // A real Firestore `.snapshots()` listener always receives the current
    // state immediately on subscribe, not just future changes — replicated
    // here via a single-subscription wrapper that emits the current
    // snapshot first, then forwards the broadcast controller's stream.
    return Stream<List<CartItem>>.multi((emitter) {
      emitter.add(_linesByTableSession[tableSessionId]?.values.toList() ??
          const <CartItem>[]);
      final sub = controller.stream.listen(
        emitter.add,
        onError: emitter.addError,
        onDone: emitter.close,
      );
      emitter.onCancel = sub.cancel;
    });
  }

  @override
  Future<void> upsertLine({
    required String tableSessionId,
    required CartItem item,
  }) async {
    final addedBySubAccountId = item.addedBySubAccountId!;
    final lineId = deterministicCartLineId(
      addedBySubAccountId: addedBySubAccountId,
      customizationsKey: item.customizationsKey,
    );
    final lines = _linesByTableSession.putIfAbsent(tableSessionId, () => {});
    final existing = lines[lineId];
    lines[lineId] = item.copyWith(
      quantity: (existing?.quantity ?? 0) + item.quantity,
    );
    _emitCurrent(tableSessionId);
  }

  @override
  Future<void> adjustLineQuantity({
    required String tableSessionId,
    required String addedBySubAccountId,
    required String customizationsKey,
    required int delta,
  }) async {
    final lineId = deterministicCartLineId(
      addedBySubAccountId: addedBySubAccountId,
      customizationsKey: customizationsKey,
    );
    final lines = _linesByTableSession[tableSessionId];
    final existing = lines?[lineId];
    if (lines == null || existing == null) return;
    lines[lineId] = existing.copyWith(quantity: existing.quantity + delta);
    _emitCurrent(tableSessionId);
  }

  @override
  Future<void> setLineQuantity({
    required String tableSessionId,
    required String addedBySubAccountId,
    required String customizationsKey,
    required int quantity,
  }) async {
    final lineId = deterministicCartLineId(
      addedBySubAccountId: addedBySubAccountId,
      customizationsKey: customizationsKey,
    );
    final lines = _linesByTableSession[tableSessionId];
    final existing = lines?[lineId];
    if (lines == null || existing == null) return;
    lines[lineId] = existing.copyWith(quantity: quantity);
    _emitCurrent(tableSessionId);
  }

  @override
  Future<void> removeLine({
    required String tableSessionId,
    required String addedBySubAccountId,
    required String customizationsKey,
  }) async {
    final lineId = deterministicCartLineId(
      addedBySubAccountId: addedBySubAccountId,
      customizationsKey: customizationsKey,
    );
    _linesByTableSession[tableSessionId]?.remove(lineId);
    _emitCurrent(tableSessionId);
  }

  /// Test-only convenience — a synchronous snapshot of the current lines,
  /// for assertions that don't want to deal with [watchLines]' stream.
  List<CartItem> linesFor(String tableSessionId) {
    return _linesByTableSession[tableSessionId]?.values.toList() ??
        const <CartItem>[];
  }

  /// Test-only convenience — simulates `submitDineInOrder`'s own atomic,
  /// Admin-SDK deletion of the exact lines a submission consumed (Faz 4).
  /// Takes the raw Firestore document id directly (unlike [removeLine],
  /// which re-derives it) since that's exactly what the real callable
  /// receives from the client and deletes without re-deriving anything.
  void removeLineById(String tableSessionId, String lineId) {
    _linesByTableSession[tableSessionId]?.remove(lineId);
    _emitCurrent(tableSessionId);
  }

  /// Test-only convenience — seeds lines directly without going through
  /// [upsertLine]'s merge semantics, for tests that just need a fixed
  /// starting cart.
  void seed(String tableSessionId, List<CartItem> items) {
    final lines = _linesByTableSession.putIfAbsent(tableSessionId, () => {});
    for (final item in items) {
      final lineId = deterministicCartLineId(
        addedBySubAccountId: item.addedBySubAccountId!,
        customizationsKey: item.customizationsKey,
      );
      lines[lineId] = item;
    }
    _emitCurrent(tableSessionId);
  }
}
