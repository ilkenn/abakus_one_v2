import 'package:cloud_firestore/cloud_firestore.dart' as fs;

import '../../menu/domain/models/selected_modifier.dart';
import '../../orders/domain/models/order_channel.dart';
import '../domain/models/cart_item.dart';

/// Derives the stable document id for one guest's one distinct line
/// configuration within `tableSessionCarts/{tableSessionId}/lines` — Self-
/// Order QR Faz 3. Keyed on `(addedBySubAccountId, customizationsKey)` so a
/// repeat add of the EXACT same configuration by the SAME guest merges into
/// one line (mirrors the pre-existing local [CartItem]/`CartNotifier`
/// merge behavior exactly), while two different guests adding the
/// identical product/config each keep their own, separately-attributed
/// line — merging those would make "kim ne eklemiş" (who added what)
/// unreadable.
///
/// `customizationsKey` is free-form (it can embed a customer's own typed
/// note) and therefore not guaranteed to be a valid Firestore document id
/// byte-for-byte — sanitized here rather than hashed, since adding a hash
/// package is a new dependency this phase doesn't need. The only cost of
/// sanitizing instead of hashing is a theoretical collision between two
/// configurations that differ only in punctuation the sanitizer maps to
/// the same character — a cosmetic quantity-merge quirk for the same
/// guest, never a cross-guest/security issue.
String deterministicCartLineId({
  required String addedBySubAccountId,
  required String customizationsKey,
}) {
  final sanitized =
      customizationsKey.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '-');
  final truncated =
      sanitized.length > 300 ? sanitized.substring(0, 300) : sanitized;
  return '${addedBySubAccountId}__$truncated';
}

/// The live, multi-device-shared pre-submission cart for one dine-in-QR
/// table session — Self-Order QR Faz 3. Every method is scoped to a single
/// `tableSessionId` (`ActiveTableContext.session.id`), never a raw
/// `tableGuestSessions` document id.
///
/// Deliberately a direct Firestore read/write client, not a Cloud-
/// Function-mediated gateway (see `firestore.rules`' own comment on
/// `tableSessionCarts` for why that's safe here): this collection is
/// display-only staging data, never the authoritative source a real order
/// is priced from.
abstract interface class TableSessionCartFirestoreClient {
  /// A live view of every line currently in the shared cart, across every
  /// device/guest at this table session — re-emits on any add/update/
  /// remove, from any participant's device.
  Stream<List<CartItem>> watchLines(String tableSessionId);

  /// Adds [item.quantity] more of this exact configuration, attributed to
  /// [item.addedBySubAccountId] — merges (atomically increments the
  /// existing line's quantity) if this guest already has an identical-
  /// configuration line, otherwise creates a new one. Mirrors
  /// `CartNotifier.addToCart`'s own merge-by-`customizationsKey` semantics.
  Future<void> upsertLine({
    required String tableSessionId,
    required CartItem item,
  });

  /// Atomically adjusts an existing line's quantity by [delta] (positive or
  /// negative) — safe without a prior read because only the line's own
  /// adder can ever call this for their own line (enforced by
  /// `firestore.rules`, never trusted client-side alone).
  Future<void> adjustLineQuantity({
    required String tableSessionId,
    required String addedBySubAccountId,
    required String customizationsKey,
    required int delta,
  });

  /// Sets a line's quantity to an absolute value — used where the caller
  /// (not this client) already decided the final count, e.g. a direct
  /// quantity-entry field.
  Future<void> setLineQuantity({
    required String tableSessionId,
    required String addedBySubAccountId,
    required String customizationsKey,
    required int quantity,
  });

  Future<void> removeLine({
    required String tableSessionId,
    required String addedBySubAccountId,
    required String customizationsKey,
  });
}

class DefaultTableSessionCartFirestoreClient
    implements TableSessionCartFirestoreClient {
  DefaultTableSessionCartFirestoreClient({fs.FirebaseFirestore? firestore})
      : _providedFirestore = firestore;

  // Resolved lazily — mirrors `DefaultTableGuestSessionFirestoreClient`'s
  // exact reasoning: `fs.FirebaseFirestore.instance` throws with no real
  // Firebase app yet, and a provider-wiring test must not crash at
  // construction.
  final fs.FirebaseFirestore? _providedFirestore;
  fs.FirebaseFirestore get _firestore =>
      _providedFirestore ?? fs.FirebaseFirestore.instance;

  fs.CollectionReference<Map<String, dynamic>> _linesRef(
    String tableSessionId,
  ) {
    return _firestore
        .collection('tableSessionCarts')
        .doc(tableSessionId)
        .collection('lines');
  }

  @override
  Stream<List<CartItem>> watchLines(String tableSessionId) {
    return _linesRef(tableSessionId)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(_parse).toList());
  }

  @override
  Future<void> upsertLine({
    required String tableSessionId,
    required CartItem item,
  }) async {
    final addedBySubAccountId = item.addedBySubAccountId;
    if (addedBySubAccountId == null) {
      throw ArgumentError.value(
        item,
        'item',
        'addedBySubAccountId is required to write a shared table cart line.',
      );
    }
    final lineId = deterministicCartLineId(
      addedBySubAccountId: addedBySubAccountId,
      customizationsKey: item.customizationsKey,
    );
    await _linesRef(tableSessionId).doc(lineId).set({
      'addedBySubAccountId': addedBySubAccountId,
      'productId': item.id,
      'name': item.name,
      'desc': item.desc,
      'price': item.price,
      'quantity': fs.FieldValue.increment(item.quantity),
      'selectedProtein': item.selectedProtein,
      'selectedSauce': item.selectedSauce,
      'removedIngredients': item.removedIngredients,
      'extraIngredients': item.extraIngredients,
      'extraCostPerUnit': item.extraCostPerUnit,
      'selectedModifiers': item.selectedModifiers.map(_modifierToMap).toList(),
      'note': item.note,
      'customizationsKey': item.customizationsKey,
      'createdAt': fs.FieldValue.serverTimestamp(),
    }, fs.SetOptions(merge: true));
  }

  @override
  Future<void> adjustLineQuantity({
    required String tableSessionId,
    required String addedBySubAccountId,
    required String customizationsKey,
    required int delta,
  }) {
    final lineId = deterministicCartLineId(
      addedBySubAccountId: addedBySubAccountId,
      customizationsKey: customizationsKey,
    );
    return _linesRef(tableSessionId).doc(lineId).update({
      'quantity': fs.FieldValue.increment(delta),
    });
  }

  @override
  Future<void> setLineQuantity({
    required String tableSessionId,
    required String addedBySubAccountId,
    required String customizationsKey,
    required int quantity,
  }) {
    final lineId = deterministicCartLineId(
      addedBySubAccountId: addedBySubAccountId,
      customizationsKey: customizationsKey,
    );
    return _linesRef(tableSessionId).doc(lineId).update({
      'quantity': quantity,
    });
  }

  @override
  Future<void> removeLine({
    required String tableSessionId,
    required String addedBySubAccountId,
    required String customizationsKey,
  }) {
    final lineId = deterministicCartLineId(
      addedBySubAccountId: addedBySubAccountId,
      customizationsKey: customizationsKey,
    );
    return _linesRef(tableSessionId).doc(lineId).delete();
  }

  Map<String, dynamic> _modifierToMap(SelectedModifier modifier) {
    return {
      'groupId': modifier.groupId,
      'groupName': modifier.groupName,
      'optionId': modifier.optionId,
      'optionName': modifier.optionName,
      'extraPrice': modifier.extraPrice,
    };
  }

  SelectedModifier _modifierFromMap(Map<String, dynamic> map) {
    return SelectedModifier(
      groupId: map['groupId'] as String,
      groupName: map['groupName'] as String,
      optionId: map['optionId'] as String,
      optionName: map['optionName'] as String,
      extraPrice: (map['extraPrice'] as num?)?.toDouble() ?? 0.0,
    );
  }

  CartItem _parse(fs.QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final rawModifiers = data['selectedModifiers'] as List<dynamic>? ?? [];
    return CartItem(
      id: data['productId'] as String,
      name: data['name'] as String,
      desc: data['desc'] as String? ?? '',
      price: (data['price'] as num).toDouble(),
      quantity: (data['quantity'] as num).toInt(),
      selectedProtein: data['selectedProtein'] as String? ?? '',
      selectedSauce: data['selectedSauce'] as String? ?? '',
      removedIngredients:
          (data['removedIngredients'] as List<dynamic>? ?? []).cast<String>(),
      extraIngredients:
          (data['extraIngredients'] as List<dynamic>? ?? []).cast<String>(),
      extraCostPerUnit: (data['extraCostPerUnit'] as num?)?.toDouble() ?? 0.0,
      selectedModifiers: rawModifiers
          .map((m) => _modifierFromMap(m as Map<String, dynamic>))
          .toList(),
      note: data['note'] as String? ?? '',
      customizationsKey: data['customizationsKey'] as String? ?? '',
      pricedForChannel: OrderChannel.dineInQr,
      addedBySubAccountId: data['addedBySubAccountId'] as String,
    );
  }
}
