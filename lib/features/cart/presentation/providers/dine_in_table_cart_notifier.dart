import 'dart:async';

import '../../../../core/services/logging/log_level.dart';
import '../../../../core/services/logging/logging_provider.dart';
import '../../../menu/domain/models/selected_modifier.dart';
import '../../../orders/domain/models/order_channel.dart';
import '../../../qr/domain/identity/dine_in_sub_account_id.dart';
import '../../../qr/domain/models/active_table_context.dart';
import '../../../qr/presentation/providers/active_table_context_provider.dart';
import '../../../qr/presentation/providers/table_guest_session_dependencies_provider.dart';
import '../../domain/models/cart_item.dart';
import 'cart_provider.dart';
import 'table_session_cart_dependencies_provider.dart';

/// Self-Order QR Faz 3 — the real app's `cartProvider` is wired to THIS
/// subclass (never `preorderCartProvider`, which deliberately keeps using
/// the plain base `CartNotifier` — its own doc comment explains why that
/// isolation must stay untouched; this class is simply never passed to
/// it).
///
/// While `activeTableContextProvider` is null, every method below
/// delegates straight to `super`, so takeaway/delivery/personal-dine-in
/// behavior is byte-for-byte unchanged — "Desenin yalnızca dineInQr kanalı
/// için scoped olması" (explicit user requirement). The instant a table
/// context becomes active, this starts mirroring the live, multi-device-
/// shared `tableSessionCarts/{tableSessionId}/lines` collection instead of
/// a private local list.
///
/// **Supersedes a documented-but-now-stale design note**:
/// `docs/table_qr_architecture.md` originally described `GuestSession`
/// (not `TableSession`) as the unit that owns cart/order context, "because
/// a table visit can hold multiple guests... each browsing and ordering
/// independently." Faz 3 is an explicit, user-directed widening of that:
/// the real cart for the dine-in-QR channel is now table-session-scoped
/// and genuinely shared — `GuestSession.currentCartId` is not written or
/// read by this class and becomes vestigial for this channel.
class DineInTableCartNotifier extends CartNotifier {
  StreamSubscription<List<CartItem>>? _subscription;
  String? _activeTableSessionId;

  @override
  List<CartItem> build() {
    ref.onDispose(() => _subscription?.cancel());
    ref.listen<ActiveTableContext?>(
      activeTableContextProvider,
      // 2026-11-11 — the REAL table session id, never `session.id` (the
      // caller's tableGuestSessions id): firestore.rules keys this
      // collection and its sub-account check by the table session.
      (previous, next) => _syncTableSession(next?.sharedCartTableSessionId),
      fireImmediately: true,
    );
    return super.build();
  }

  void _syncTableSession(String? tableSessionId) {
    if (tableSessionId == _activeTableSessionId) return;
    _subscription?.cancel();
    _subscription = null;
    _activeTableSessionId = tableSessionId;
    if (tableSessionId == null) {
      // Leaving the shared table session always starts the next channel
      // with a genuinely empty local cart — mirrors every other channel's
      // own post-`clearCart` expectation; never carries a stale shared-
      // table snapshot forward into takeaway/delivery/personal shopping.
      state = const [];
      return;
    }
    _subscription = ref
        .read(tableSessionCartFirestoreClientProvider)
        .watchLines(tableSessionId)
        .listen(
          (lines) => state = lines,
          // 2026-11-11 — a denied/failed snapshot listener used to surface
          // as an uncaught exception. Logged; the last known lines stay.
          onError: (Object error, StackTrace stackTrace) => _logFailure(
            'watchLines',
            error,
            stackTrace,
          ),
        );
  }

  /// 2026-11-11 — every shared-cart write is fire-and-forget (the live
  /// listener is the source of truth for [state]); a rejected write is
  /// logged instead of becoming an uncaught async error.
  void _write(String operation, Future<void> write) {
    unawaited(write.catchError((Object error, StackTrace stackTrace) {
      _logFailure(operation, error, stackTrace);
    }));
  }

  void _logFailure(String operation, Object error, StackTrace stackTrace) {
    ref.read(loggingServiceProvider).log(
      LogLevel.error,
      'DineInTableCartNotifier.$operation failed',
      error: error,
      stackTrace: stackTrace,
      context: {'tableSessionId': _activeTableSessionId},
    );
  }

  /// `null` whenever there's no active table session, or (should not
  /// happen once a table context exists — `openTableGuestSession` requires
  /// a caller uid — but never assumed) nobody is signed in to Firebase
  /// Auth yet.
  String? get _currentSubAccountId {
    final tableSessionId = _activeTableSessionId;
    if (tableSessionId == null) return null;
    final uid = ref.read(technicalIdentityProviderProvider).currentUid;
    if (uid == null) return null;
    return deterministicIdentitySubAccountId(
      tableSessionId: tableSessionId,
      uid: uid,
    );
  }

  bool _ownsLine(String targetKey, String subAccountId) {
    return state.any((item) =>
        item.customizationsKey == targetKey &&
        item.addedBySubAccountId == subAccountId);
  }

  CartItem? _findOwnLine(String targetKey, String subAccountId) {
    for (final item in state) {
      if (item.customizationsKey == targetKey &&
          item.addedBySubAccountId == subAccountId) {
        return item;
      }
    }
    return null;
  }

  @override
  void addToCart({
    required String id,
    required String name,
    required String desc,
    required double price,
    int quantity = 1,
    String selectedProtein = '',
    String selectedSauce = '',
    List<String> removedIngredients = const [],
    List<String> extraIngredients = const [],
    double extraCostPerUnit = 0.0,
    List<SelectedModifier> selectedModifiers = const [],
    String note = '',
    String customizationsKey = '',
    OrderChannel? pricedForChannel,
  }) {
    final tableSessionId = _activeTableSessionId;
    final subAccountId = _currentSubAccountId;
    if (tableSessionId == null || subAccountId == null) {
      super.addToCart(
        id: id,
        name: name,
        desc: desc,
        price: price,
        quantity: quantity,
        selectedProtein: selectedProtein,
        selectedSauce: selectedSauce,
        removedIngredients: removedIngredients,
        extraIngredients: extraIngredients,
        extraCostPerUnit: extraCostPerUnit,
        selectedModifiers: selectedModifiers,
        note: note,
        customizationsKey: customizationsKey,
        pricedForChannel: pricedForChannel,
      );
      return;
    }

    final targetKey = computeCustomizationsKey(
      id: id,
      selectedProtein: selectedProtein,
      selectedSauce: selectedSauce,
      removedIngredients: removedIngredients,
      extraIngredients: extraIngredients,
      selectedModifiers: selectedModifiers,
      note: note,
      customizationsKey: customizationsKey,
    );

    _write(
      'upsertLine',
      ref.read(tableSessionCartFirestoreClientProvider).upsertLine(
            tableSessionId: tableSessionId,
            item: CartItem(
              id: id,
              name: name,
              desc: desc,
              price: price,
              quantity: quantity,
              selectedProtein: selectedProtein,
              selectedSauce: selectedSauce,
              removedIngredients: removedIngredients,
              extraIngredients: extraIngredients,
              extraCostPerUnit: extraCostPerUnit,
              selectedModifiers: selectedModifiers,
              note: note,
              customizationsKey: targetKey,
              pricedForChannel: OrderChannel.dineInQr,
              addedBySubAccountId: subAccountId,
            ),
          ),
    );
  }

  @override
  void incrementQuantity(String targetKey) {
    final tableSessionId = _activeTableSessionId;
    final subAccountId = _currentSubAccountId;
    if (tableSessionId == null || subAccountId == null) {
      super.incrementQuantity(targetKey);
      return;
    }
    if (!_ownsLine(targetKey, subAccountId)) return;
    _write(
      'adjustLineQuantity',
      ref.read(tableSessionCartFirestoreClientProvider).adjustLineQuantity(
            tableSessionId: tableSessionId,
            addedBySubAccountId: subAccountId,
            customizationsKey: targetKey,
            delta: 1,
          ),
    );
  }

  @override
  void decrementQuantity(String targetKey) {
    final tableSessionId = _activeTableSessionId;
    final subAccountId = _currentSubAccountId;
    if (tableSessionId == null || subAccountId == null) {
      super.decrementQuantity(targetKey);
      return;
    }
    final myLine = _findOwnLine(targetKey, subAccountId);
    if (myLine == null) return;
    final client = ref.read(tableSessionCartFirestoreClientProvider);
    if (myLine.quantity <= 1) {
      _write(
          'removeLine',
          client.removeLine(
            tableSessionId: tableSessionId,
            addedBySubAccountId: subAccountId,
            customizationsKey: targetKey,
          ));
      return;
    }
    _write(
        'adjustLineQuantity',
        client.adjustLineQuantity(
          tableSessionId: tableSessionId,
          addedBySubAccountId: subAccountId,
          customizationsKey: targetKey,
          delta: -1,
        ));
  }

  @override
  void updateQuantity(
      String id, String protein, String sauce, int newQuantity) {
    final tableSessionId = _activeTableSessionId;
    final subAccountId = _currentSubAccountId;
    if (tableSessionId == null || subAccountId == null) {
      super.updateQuantity(id, protein, sauce, newQuantity);
      return;
    }
    CartItem? myLine;
    for (final item in state) {
      if (item.id == id &&
          item.selectedProtein == protein &&
          item.selectedSauce == sauce &&
          item.addedBySubAccountId == subAccountId) {
        myLine = item;
        break;
      }
    }
    if (myLine == null) return;
    final client = ref.read(tableSessionCartFirestoreClientProvider);
    if (newQuantity <= 0) {
      _write(
          'removeLine',
          client.removeLine(
            tableSessionId: tableSessionId,
            addedBySubAccountId: subAccountId,
            customizationsKey: myLine.customizationsKey,
          ));
      return;
    }
    _write(
        'setLineQuantity',
        client.setLineQuantity(
          tableSessionId: tableSessionId,
          addedBySubAccountId: subAccountId,
          customizationsKey: myLine.customizationsKey,
          quantity: newQuantity,
        ));
  }

  @override
  void removeFromCart({
    String? id,
    String? selectedProtein,
    String? selectedSauce,
    String? customizationsKey,
  }) {
    final tableSessionId = _activeTableSessionId;
    final subAccountId = _currentSubAccountId;
    if (tableSessionId == null || subAccountId == null) {
      super.removeFromCart(
        id: id,
        selectedProtein: selectedProtein,
        selectedSauce: selectedSauce,
        customizationsKey: customizationsKey,
      );
      return;
    }
    final client = ref.read(tableSessionCartFirestoreClientProvider);
    if (customizationsKey != null && customizationsKey.isNotEmpty) {
      if (!_ownsLine(customizationsKey, subAccountId)) return;
      _write(
          'removeLine',
          client.removeLine(
            tableSessionId: tableSessionId,
            addedBySubAccountId: subAccountId,
            customizationsKey: customizationsKey,
          ));
      return;
    }
    if (id == null) return;
    // Mirrors the base class's own id/protein/sauce fallback matching
    // exactly, scoped to a line this device's own sub-account added.
    CartItem? ownedLine;
    for (final item in state) {
      if (item.id == id &&
          item.selectedProtein == (selectedProtein ?? '') &&
          item.selectedSauce == (selectedSauce ?? '') &&
          item.addedBySubAccountId == subAccountId) {
        ownedLine = item;
        break;
      }
    }
    if (ownedLine == null) return;
    _write(
        'removeLine',
        client.removeLine(
          tableSessionId: tableSessionId,
          addedBySubAccountId: subAccountId,
          customizationsKey: ownedLine.customizationsKey,
        ));
  }

  @override
  void clearCart() {
    final tableSessionId = _activeTableSessionId;
    final subAccountId = _currentSubAccountId;
    if (tableSessionId == null || subAccountId == null) {
      super.clearCart();
      return;
    }
    // Faz 3 interim scope (disclosed — `docs/feature_status.md`): only MY
    // OWN lines can ever be deleted (the security rule enforces this
    // regardless of what this method attempts), so this clears what I
    // personally added, never a tablemate's still-open line. Faz 4's
    // hybrid-submission flow replaces this call site with a submission-
    // scoped clear that matches each of its two modes precisely.
    final client = ref.read(tableSessionCartFirestoreClientProvider);
    for (final line in state) {
      if (line.addedBySubAccountId == subAccountId) {
        _write(
            'removeLine',
            client.removeLine(
              tableSessionId: tableSessionId,
              addedBySubAccountId: subAccountId,
              customizationsKey: line.customizationsKey,
            ));
      }
    }
  }
}
