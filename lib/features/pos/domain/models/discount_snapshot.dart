import '../../../../core/errors/business_rule_violation.dart';
import '../../../../shared/models/money.dart';
import '../../../orders/domain/discounts/discount.dart';

/// An immutable, frozen record of one discount applied within a
/// [PosOrderSession] — replaces the session's old single `Discount?`
/// field (`docs/decisions.md` ADR-012).
///
/// At most one line-scoped [DiscountSnapshot] may be active per
/// `targetOrderLineId`, and at most one order-scoped snapshot may be
/// active per session — `SetPosDiscount` enforces "replace, never stack"
/// for both, not this class itself (a plain value object has no session
/// context to check against).
///
/// **Append-only**: never mutated once created. Replacing a line's active
/// discount means the session's `discounts` list drops the old snapshot
/// and adds a new one — the old one is discarded from the *session*, but
/// nothing here mutates a snapshot in place.
class DiscountSnapshot {
  /// A percentage discount (e.g. a quick-discount preset).
  /// [percentageBasisPoints]: hundredths of a percent (10.00% = 1000),
  /// matching `Discount`'s own convention. [discountAmount] is the
  /// already-computed, frozen amount this percentage produced against
  /// whatever base it was applied to — never recomputed later.
  factory DiscountSnapshot.percentage({
    required String discountId,
    required String discountName,
    required int percentageBasisPoints,
    required Money discountAmount,
    required DiscountScope scope,
    String? targetOrderLineId,
    required String appliedByStaffId,
    required DateTime appliedAt,
  }) {
    _validateScopeTarget(scope, targetOrderLineId);
    return DiscountSnapshot._(
      discountId: discountId,
      discountName: discountName,
      type: DiscountType.percentage,
      percentageBasisPoints: percentageBasisPoints,
      discountAmount: discountAmount,
      scope: scope,
      targetOrderLineId: targetOrderLineId,
      appliedByStaffId: appliedByStaffId,
      appliedAt: appliedAt,
    );
  }

  /// A fixed-amount discount — reserved for a future order-level discount
  /// UI (not built this sprint; quick product discounts are always
  /// percentage-based, see `docs/business_rules.md`).
  factory DiscountSnapshot.fixedAmount({
    required String discountId,
    required String discountName,
    required Money discountAmount,
    required DiscountScope scope,
    String? targetOrderLineId,
    required String appliedByStaffId,
    required DateTime appliedAt,
  }) {
    _validateScopeTarget(scope, targetOrderLineId);
    return DiscountSnapshot._(
      discountId: discountId,
      discountName: discountName,
      type: DiscountType.fixedAmount,
      percentageBasisPoints: null,
      discountAmount: discountAmount,
      scope: scope,
      targetOrderLineId: targetOrderLineId,
      appliedByStaffId: appliedByStaffId,
      appliedAt: appliedAt,
    );
  }

  const DiscountSnapshot._({
    required this.discountId,
    required this.discountName,
    required this.type,
    required this.percentageBasisPoints,
    required this.discountAmount,
    required this.scope,
    required this.targetOrderLineId,
    required this.appliedByStaffId,
    required this.appliedAt,
  });

  static void _validateScopeTarget(
      DiscountScope scope, String? targetOrderLineId) {
    if (scope == DiscountScope.line && targetOrderLineId == null) {
      throw const LineDiscountMissingTargetViolation();
    }
    if (scope == DiscountScope.order && targetOrderLineId != null) {
      throw const OrderDiscountMustNotTargetLineViolation();
    }
  }

  final String discountId;
  final String discountName;
  final DiscountType type;

  /// Non-null if and only if [type] is [DiscountType.percentage].
  final int? percentageBasisPoints;

  /// The already-computed amount this discount reduces its target by —
  /// frozen at application time, never recomputed from a live base later.
  final Money discountAmount;

  final DiscountScope scope;

  /// Non-null if and only if [scope] is [DiscountScope.line].
  final String? targetOrderLineId;

  final String appliedByStaffId;
  final DateTime appliedAt;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is DiscountSnapshot &&
            other.discountId == discountId &&
            other.discountName == discountName &&
            other.type == type &&
            other.percentageBasisPoints == percentageBasisPoints &&
            other.discountAmount == discountAmount &&
            other.scope == scope &&
            other.targetOrderLineId == targetOrderLineId &&
            other.appliedByStaffId == appliedByStaffId &&
            other.appliedAt == appliedAt);
  }

  @override
  int get hashCode => Object.hash(
        discountId,
        discountName,
        type,
        percentageBasisPoints,
        discountAmount,
        scope,
        targetOrderLineId,
        appliedByStaffId,
        appliedAt,
      );
}
