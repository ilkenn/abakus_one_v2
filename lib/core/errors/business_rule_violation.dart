/// A violation of a restaurant-domain business rule — an invalid state a
/// domain model refuses to construct or transition into (a negative total,
/// an out-of-order status transition, a currency mismatch, an unsatisfied
/// modifier group, ...).
///
/// Distinct from `Failure` (`core/errors/failure.dart`): `Failure` maps a
/// *technical* exception (network, platform, unexpected) into a user-safe
/// message via `ErrorMapper`. `BusinessRuleViolation` is thrown directly by
/// domain models themselves when the caller asks them to represent
/// something the business rules (`docs/business_rules.md`) say can't exist
/// — a programming-time contract violation, not a runtime infrastructure
/// failure. The two are never conflated: nothing here has a user-facing
/// message field, and `ErrorMapper` does not map this type today (a
/// `BusinessRuleViolation` reaching a UI boundary uncaught is a bug in the
/// caller, not an expected runtime condition to translate).
///
/// Implements [Exception] so every subtype can be `throw`n directly and
/// caught with `on BusinessRuleViolation catch (e)`.
///
/// **No field here is typed as a feature-layer enum** (e.g. `OrderStatus`,
/// `OrderChannel`) even where a violation is conceptually about one —
/// `core/` may not import `features/` (see `CLAUDE.md` §3). Every such
/// value is carried as its raw `.name` string instead, mirroring how
/// `OrderAuditEntry.previousValue`/`newValue` already do the same thing for
/// the same reason.
///
/// Closed, `switch`-exhaustive hierarchy — a call site that branches on a
/// `BusinessRuleViolation` gets an analyzer error if a new subtype is added
/// and left unhandled.
sealed class BusinessRuleViolation implements Exception {
  const BusinessRuleViolation();

  /// A short, technical, English description — for logs/debugging, not for
  /// display to an end user (see this class's own doc comment on why it
  /// has no user-facing message field at all).
  String get description;

  @override
  String toString() => '$runtimeType: $description';
}

/// A computed grand total (or an intermediate amount that must never be
/// negative) would be negative.
final class NegativeTotalViolation extends BusinessRuleViolation {
  const NegativeTotalViolation(
      {required this.minorUnits, required this.currencyCode});

  final int minorUnits;
  final String currencyCode;

  @override
  String get description =>
      'Computed total is negative: $minorUnits minor units of $currencyCode';
}

/// Two [Money]/rate values that must share a currency did not.
final class CurrencyMismatchViolation extends BusinessRuleViolation {
  const CurrencyMismatchViolation({
    required this.expectedCurrencyCode,
    required this.actualCurrencyCode,
  });

  final String expectedCurrencyCode;
  final String actualCurrencyCode;

  @override
  String get description =>
      'Expected currency $expectedCurrencyCode but got $actualCurrencyCode';
}

/// An `Order` was asked to move from one [OrderStatus] to another that
/// `OrderStatusTransitions.canTransition` does not permit.
final class InvalidOrderStatusTransitionViolation
    extends BusinessRuleViolation {
  const InvalidOrderStatusTransitionViolation({
    required this.fromStatusName,
    required this.toStatusName,
  });

  final String fromStatusName;
  final String toStatusName;

  @override
  String get description =>
      'Invalid order status transition: $fromStatusName -> $toStatusName';
}

/// A quantity that must be positive (an [OrderLine]'s item count, a
/// modifier selection's count) was zero or negative.
final class NonPositiveQuantityViolation extends BusinessRuleViolation {
  const NonPositiveQuantityViolation(
      {required this.context, required this.quantity});

  /// Short, human-readable description of what the quantity was for (e.g.
  /// `'OrderLine.quantity'`).
  final String context;
  final int quantity;

  @override
  String get description => '$context must be positive, got $quantity';
}

/// A caller-supplied amount that must never be negative (a line/order
/// discount, a fee, a tip) was negative — distinct from
/// [NegativeTotalViolation], which is about a *computed* total going
/// negative after combining several amounts.
final class NegativeAmountViolation extends BusinessRuleViolation {
  const NegativeAmountViolation({
    required this.context,
    required this.minorUnits,
    required this.currencyCode,
  });

  final String context;
  final int minorUnits;
  final String currencyCode;

  @override
  String get description =>
      '$context must not be negative: $minorUnits minor units of $currencyCode';
}

/// An `Order`/`OrderLine` was constructed with no lines, or a required
/// identity value (an [OrderId]/[OrderNumber]/receipt number) was empty.
final class EmptyIdentifierViolation extends BusinessRuleViolation {
  const EmptyIdentifierViolation({required this.identifierName});

  final String identifierName;

  @override
  String get description => '$identifierName must not be empty';
}

/// An `Order` was constructed with no [OrderLine]s.
final class EmptyOrderViolation extends BusinessRuleViolation {
  const EmptyOrderViolation();

  @override
  String get description => 'An order must have at least one line';
}

/// A required modifier group ([ModifierGroup.isRequired]) had no selection.
final class RequiredModifierGroupMissingViolation
    extends BusinessRuleViolation {
  const RequiredModifierGroupMissingViolation({required this.groupId});

  final String groupId;

  @override
  String get description =>
      'Required modifier group "$groupId" has no selection';
}

/// A modifier group's selected quantity fell outside
/// `[minSelections, maxSelections]`.
final class ModifierSelectionCountViolation extends BusinessRuleViolation {
  const ModifierSelectionCountViolation({
    required this.groupId,
    required this.selectedCount,
    required this.minSelections,
    required this.maxSelections,
  });

  final String groupId;
  final int selectedCount;
  final int minSelections;
  final int maxSelections;

  @override
  String get description =>
      'Modifier group "$groupId" selection count $selectedCount is outside '
      '[$minSelections, $maxSelections]';
}

/// A modifier group was selected from on a channel not in
/// [ModifierGroup.visibleChannels].
final class ModifierGroupUnavailableInChannelViolation
    extends BusinessRuleViolation {
  const ModifierGroupUnavailableInChannelViolation({
    required this.groupId,
    required this.channelName,
  });

  final String groupId;
  final String channelName;

  @override
  String get description =>
      'Modifier group "$groupId" is not available on channel "$channelName"';
}

/// A selected [ModifierOption] does not belong to the group it was
/// selected from.
final class UnknownModifierOptionViolation extends BusinessRuleViolation {
  const UnknownModifierOptionViolation({
    required this.groupId,
    required this.optionId,
  });

  final String groupId;
  final String optionId;

  @override
  String get description =>
      'Option "$optionId" does not belong to modifier group "$groupId"';
}

/// A selected [ModifierOption] exists but [ModifierOption.isAvailable] is
/// `false`.
final class ModifierOptionUnavailableViolation extends BusinessRuleViolation {
  const ModifierOptionUnavailableViolation({required this.optionId});

  final String optionId;

  @override
  String get description => 'Modifier option "$optionId" is not available';
}

/// A modifier selection's quantity was zero or negative.
final class InvalidModifierQuantityViolation extends BusinessRuleViolation {
  const InvalidModifierQuantityViolation({
    required this.optionId,
    required this.quantity,
  });

  final String optionId;
  final int quantity;

  @override
  String get description =>
      'Modifier option "$optionId" has invalid quantity $quantity';
}

/// More than one order-level [Discount] was presented to
/// `SingleDiscountOnlyPolicy` — see `docs/business_rules.md` BR-PROMO-004
/// (UNRESOLVED: whether multiple discounts may stack).
final class MultipleDiscountsNotSupportedViolation
    extends BusinessRuleViolation {
  const MultipleDiscountsNotSupportedViolation({required this.discountCount});

  final int discountCount;

  @override
  String get description =>
      'Discount stacking is not supported: $discountCount discounts presented';
}

/// An `ExchangeRateSnapshot`'s computed acceptance rate
/// (`marketSellingRate - fixedMargin`) was zero or negative.
final class NonPositiveAcceptanceRateViolation extends BusinessRuleViolation {
  const NonPositiveAcceptanceRateViolation({
    required this.marketSellingRateMinorUnits,
    required this.fixedMarginMinorUnits,
  });

  final int marketSellingRateMinorUnits;
  final int fixedMarginMinorUnits;

  @override
  String get description =>
      'Non-positive acceptance rate: market $marketSellingRateMinorUnits - '
      'margin $fixedMarginMinorUnits minor units';
}

/// An `ExchangeRateSnapshot` was constructed with a target currency other
/// than TRY, or a source currency equal to TRY — this app only models
/// foreign-to-TRY conversion (see the approved multi-currency payment
/// decision: "Accounting and menu pricing remain TRY-based").
final class UnsupportedExchangeRateCurrencyViolation
    extends BusinessRuleViolation {
  const UnsupportedExchangeRateCurrencyViolation({
    required this.sourceCurrencyCode,
    required this.targetCurrencyCode,
  });

  final String sourceCurrencyCode;
  final String targetCurrencyCode;

  @override
  String get description => 'Unsupported exchange rate currency pair: '
      '$sourceCurrencyCode -> $targetCurrencyCode';
}

/// A `PaymentSplit` was tendered in a non-TRY currency with no
/// `ExchangeRateSnapshot` attached.
final class ForeignCurrencyPaymentMissingExchangeRateViolation
    extends BusinessRuleViolation {
  const ForeignCurrencyPaymentMissingExchangeRateViolation({
    required this.currencyCode,
  });

  final String currencyCode;

  @override
  String get description =>
      'Payment in $currencyCode requires an ExchangeRateSnapshot';
}

/// A `Currency` with `isAcceptedByBusiness == false` was used somewhere
/// that requires business acceptance — capturing an `ExchangeRateSnapshot`
/// for it, or tendering a `PaymentSplit` in it.
final class CurrencyNotAcceptedViolation extends BusinessRuleViolation {
  const CurrencyNotAcceptedViolation({required this.currencyCode});

  final String currencyCode;

  @override
  String get description =>
      'Currency $currencyCode is not currently accepted by the business';
}
