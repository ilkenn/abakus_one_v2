import 'customer_account_status.dart';
import 'customer_category.dart';

/// A customer's CRM registry entry — the first `Customer` entity of any
/// kind in this codebase (Sprint 5D). Before this, "customer" only ever
/// meant "the current device's own signed-in session"
/// (`AuthNotifier`/`ProfileModel`) — no multi-instance customer registry
/// existed anywhere, so an administrator had no customer to filter or
/// list. This mirrors exactly how `Courier` (Phase 5,
/// `docs/decisions.md` ADR-020) was this codebase's first real courier
/// registry entity.
///
/// Mutable registry entity, mirroring `Courier`'s own shape: a customer's
/// own current shape is what matters, not a revision history of it — the
/// append-only requirement in this feature applies to the *engagement*
/// records a customer's visits/rewards/feedback/survey-responses produce
/// (see `CustomerVisit`, `CustomerRewardGrant`, etc.), not to this
/// registry entry itself.
///
/// [category]/[customCategoryLabel] are both nullable and independently
/// settable at any time — "completely optional," never required at
/// registration.
class Customer {
  const Customer({
    required this.id,
    required this.displayName,
    required this.phoneNumber,
    this.category,
    this.customCategoryLabel,
    this.accountStatus = CustomerAccountStatus.active,
    required this.registeredAt,
    required this.revision,
  });

  final String id;
  final String displayName;
  final String phoneNumber;

  final CustomerCategory? category;

  /// Free-text note, only meaningful when [category] is
  /// [CustomerCategory.other] — never populated for any other category.
  final String? customCategoryLabel;

  /// **Phase 6F**: additive field — every pre-existing `Customer`
  /// construction defaults to [CustomerAccountStatus.active], so no
  /// existing call site needed to change.
  final CustomerAccountStatus accountStatus;

  final DateTime registeredAt;
  final int revision;

  Customer copyWith({
    String? displayName,
    String? phoneNumber,
    CustomerCategory? category,
    bool clearCategory = false,
    String? customCategoryLabel,
    bool clearCustomCategoryLabel = false,
    CustomerAccountStatus? accountStatus,
    required int revision,
  }) {
    return Customer(
      id: id,
      displayName: displayName ?? this.displayName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      category: clearCategory ? null : (category ?? this.category),
      customCategoryLabel: clearCustomCategoryLabel
          ? null
          : (customCategoryLabel ?? this.customCategoryLabel),
      accountStatus: accountStatus ?? this.accountStatus,
      registeredAt: registeredAt,
      revision: revision,
    );
  }
}
