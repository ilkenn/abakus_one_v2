/// Lifecycle status of a [GuestSession].
enum GuestSessionStatus { active, claimed, expired, closed }

/// An anonymous (or later account-linked) visitor session created the
/// moment a customer's QR scan resolves to a table.
///
/// A [GuestSession] is deliberately the unit that owns cart/order/language
/// context — not [TableSession] — because a table visit can hold multiple
/// guests, each browsing and ordering independently, while still sharing
/// the same [TableSession].
///
/// [authenticatedUserId] starts `null` for every QR visitor. When a guest
/// later logs in or registers mid-visit, [claim] attaches the account
/// without discarding [currentCartId], [currentOrderId], or table context —
/// the whole point of separating guest identity from account identity.
class GuestSession {
  final String id;
  final String tableSessionId;
  final String branchId;
  final String tableId;
  final String detectedLanguageCode;
  final String selectedLanguageCode;
  final String? currentCartId;
  final String? currentOrderId;
  final String? authenticatedUserId;
  final DateTime createdAt;
  final DateTime lastSeenAt;
  final GuestSessionStatus status;

  const GuestSession({
    required this.id,
    required this.tableSessionId,
    required this.branchId,
    required this.tableId,
    required this.detectedLanguageCode,
    required this.selectedLanguageCode,
    this.currentCartId,
    this.currentOrderId,
    this.authenticatedUserId,
    required this.createdAt,
    required this.lastSeenAt,
    required this.status,
  });

  bool get isAnonymous => authenticatedUserId == null;

  /// Attaches a registered account to this guest session. Cart, order, and
  /// table context are preserved untouched — only identity and status
  /// change.
  GuestSession claim({required String userId, required DateTime at}) {
    return copyWith(
      authenticatedUserId: userId,
      status: GuestSessionStatus.claimed,
      lastSeenAt: at,
    );
  }

  GuestSession touched(DateTime at) => copyWith(lastSeenAt: at);

  GuestSession closed({required DateTime at}) {
    return copyWith(status: GuestSessionStatus.closed, lastSeenAt: at);
  }

  GuestSession copyWith({
    String? id,
    String? tableSessionId,
    String? branchId,
    String? tableId,
    String? detectedLanguageCode,
    String? selectedLanguageCode,
    String? currentCartId,
    String? currentOrderId,
    String? authenticatedUserId,
    DateTime? createdAt,
    DateTime? lastSeenAt,
    GuestSessionStatus? status,
  }) {
    return GuestSession(
      id: id ?? this.id,
      tableSessionId: tableSessionId ?? this.tableSessionId,
      branchId: branchId ?? this.branchId,
      tableId: tableId ?? this.tableId,
      detectedLanguageCode: detectedLanguageCode ?? this.detectedLanguageCode,
      selectedLanguageCode: selectedLanguageCode ?? this.selectedLanguageCode,
      currentCartId: currentCartId ?? this.currentCartId,
      currentOrderId: currentOrderId ?? this.currentOrderId,
      authenticatedUserId: authenticatedUserId ?? this.authenticatedUserId,
      createdAt: createdAt ?? this.createdAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      status: status ?? this.status,
    );
  }
}
