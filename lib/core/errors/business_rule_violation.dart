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

/// A `DiscountSnapshot` with `scope == DiscountScope.line` was constructed
/// with no `targetOrderLineId`.
final class LineDiscountMissingTargetViolation extends BusinessRuleViolation {
  const LineDiscountMissingTargetViolation();

  @override
  String get description =>
      'A line-scoped discount snapshot must carry a targetOrderLineId';
}

/// A `DiscountSnapshot` with `scope == DiscountScope.order` was
/// constructed with a `targetOrderLineId` — an order-level discount never
/// targets one specific line.
final class OrderDiscountMustNotTargetLineViolation
    extends BusinessRuleViolation {
  const OrderDiscountMustNotTargetLineViolation();

  @override
  String get description =>
      'An order-scoped discount snapshot must not carry a targetOrderLineId';
}

/// A `PosOrderLineDraft`/`OrderLine` was looked up by an `orderLineDraftId`
/// that doesn't exist in the current session — a stale reference (e.g. the
/// line was already removed), not a valid index-out-of-bounds situation
/// (see `docs/decisions.md` ADR-012 on why line targeting moved off array
/// index).
final class UnknownOrderLineDraftViolation extends BusinessRuleViolation {
  const UnknownOrderLineDraftViolation({required this.orderLineDraftId});

  final String orderLineDraftId;

  @override
  String get description =>
      'No line with orderLineDraftId "$orderLineDraftId" exists in this session';
}

/// A non-cash `PaymentSplit` was added that would push
/// `PaymentSession.totalSettled` beyond `totalAmount` — only a cash split
/// may exceed the remaining balance (the excess becomes change).
final class NonCashOverpaymentViolation extends BusinessRuleViolation {
  const NonCashOverpaymentViolation({
    required this.methodId,
    required this.overpaidMinorUnits,
  });

  final String methodId;
  final int overpaidMinorUnits;

  @override
  String get description =>
      'Payment method "$methodId" cannot overpay by $overpaidMinorUnits '
      'minor units — only cash may exceed the remaining balance';
}

/// `CompletePaymentSession` was called while `PaymentSession.remainingAmount`
/// is not zero.
final class PaymentSessionNotReadyViolation extends BusinessRuleViolation {
  const PaymentSessionNotReadyViolation({required this.remainingMinorUnits});

  final int remainingMinorUnits;

  @override
  String get description =>
      'Payment session is not ready to complete: $remainingMinorUnits '
      'minor units still remaining';
}

/// A `PaymentSplit` for a method with `requiresReferenceNumberAtCapture ==
/// true` was completed with no reference number recorded.
final class MissingPaymentReferenceViolation extends BusinessRuleViolation {
  const MissingPaymentReferenceViolation({required this.methodId});

  final String methodId;

  @override
  String get description =>
      'Payment method "$methodId" requires a reference number';
}

/// A `PaymentSplit` for a method with `requiresApprovalAtCapture == true`
/// was completed with no granted `ApprovalResult` on record.
final class PaymentMethodNotApprovedViolation extends BusinessRuleViolation {
  const PaymentMethodNotApprovedViolation({required this.methodId});

  final String methodId;

  @override
  String get description =>
      'Payment method "$methodId" requires approval that was not granted';
}

/// A provider-processed `PaymentSplit` was completed while its
/// `PaymentResult.status` was not `success`.
final class ProviderTransactionNotSuccessfulViolation
    extends BusinessRuleViolation {
  const ProviderTransactionNotSuccessfulViolation({
    required this.splitId,
    required this.statusName,
  });

  final String splitId;
  final String statusName;

  @override
  String get description =>
      'Split "$splitId" has a non-successful provider result: $statusName';
}

/// `AddPaymentSplit`/`RemovePaymentSplit` was called against a
/// `PaymentSession` whose status is not `collecting`/`readyToComplete` —
/// e.g. already `completed`/`cancelled`, or mid-`completing`.
final class PaymentSessionNotEditableViolation extends BusinessRuleViolation {
  const PaymentSessionNotEditableViolation({required this.statusName});

  final String statusName;

  @override
  String get description =>
      'Payment session is not editable in status "$statusName"';
}

/// `RemovePaymentSplit` was called with a `splitId` that doesn't exist in
/// the session.
final class UnknownPaymentSplitViolation extends BusinessRuleViolation {
  const UnknownPaymentSplitViolation({required this.splitId});

  final String splitId;

  @override
  String get description =>
      'No split with id "$splitId" exists in this session';
}

/// A `PaymentSession` was asked to move from one `PaymentSessionStatus` to
/// another that `PaymentSessionStatusTransitions.canTransition` does not
/// permit.
final class InvalidPaymentSessionStatusTransitionViolation
    extends BusinessRuleViolation {
  const InvalidPaymentSessionStatusTransitionViolation({
    required this.fromStatusName,
    required this.toStatusName,
  });

  final String fromStatusName;
  final String toStatusName;

  @override
  String get description =>
      'Invalid payment session status transition: $fromStatusName -> $toStatusName';
}

/// A caller supplied an `expectedRevision` that no longer matches the
/// current stored revision of a `PaymentSession`/`OrderClosure` —
/// optimistic-concurrency guard against a stale concurrent mutation.
final class StaleRevisionViolation extends BusinessRuleViolation {
  const StaleRevisionViolation({
    required this.expectedRevision,
    required this.actualRevision,
  });

  final int expectedRevision;
  final int actualRevision;

  @override
  String get description =>
      'Stale revision: expected $expectedRevision but current is $actualRevision';
}

/// A closure lifecycle transition (`OrderClosure.lifecycleStatus`) that
/// `OrderClosureLifecycleTransitions.canTransition` does not permit was
/// attempted.
final class InvalidOrderClosureTransitionViolation
    extends BusinessRuleViolation {
  const InvalidOrderClosureTransitionViolation({
    required this.fromStatusName,
    required this.toStatusName,
  });

  final String fromStatusName;
  final String toStatusName;

  @override
  String get description =>
      'Invalid order closure transition: $fromStatusName -> $toStatusName';
}

/// A refund/void was requested for more than the still-refundable amount
/// (settled minus already refunded/voided).
final class RefundExceedsRefundableAmountViolation
    extends BusinessRuleViolation {
  const RefundExceedsRefundableAmountViolation({
    required this.requestedMinorUnits,
    required this.refundableMinorUnits,
  });

  final int requestedMinorUnits;
  final int refundableMinorUnits;

  @override
  String get description =>
      'Refund of $requestedMinorUnits minor units exceeds the refundable '
      'amount of $refundableMinorUnits minor units';
}

/// A `PosAuthorizationPolicy` denied (or a manager-approval requirement was
/// not satisfied for) an action that requires it.
final class AuthorizationDeniedViolation extends BusinessRuleViolation {
  const AuthorizationDeniedViolation({required this.actionName});

  final String actionName;

  @override
  String get description => 'Authorization denied for action "$actionName"';
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

/// A `Check`/`TableSession` lifecycle transition that the relevant
/// transitions table does not permit was attempted (Phase 3 Sprint 3D).
final class InvalidCheckStatusTransitionViolation
    extends BusinessRuleViolation {
  const InvalidCheckStatusTransitionViolation({
    required this.fromStatusName,
    required this.toStatusName,
  });

  final String fromStatusName;
  final String toStatusName;

  @override
  String get description =>
      'Invalid check status transition: $fromStatusName -> $toStatusName';
}

/// A `TableSession` was asked to close while at least one of its `Check`s
/// is not yet resolved (submitted-and-closed, or cancelled).
final class TableSessionNotReadyToCloseViolation extends BusinessRuleViolation {
  const TableSessionNotReadyToCloseViolation({
    required this.unresolvedCheckCount,
  });

  final int unresolvedCheckCount;

  @override
  String get description =>
      'Table session cannot close: $unresolvedCheckCount check(s) still '
      'unresolved';
}

/// A caller referenced a `Check`/`FloorPlan`/`RestaurantTable`/
/// `ChannelOperationPolicy`/`PackagePreparation`/`KitchenTicket` id that
/// does not exist in the relevant repository.
final class UnknownRestaurantOperationsEntityViolation
    extends BusinessRuleViolation {
  const UnknownRestaurantOperationsEntityViolation({
    required this.entityName,
    required this.id,
  });

  final String entityName;
  final String id;

  @override
  String get description => 'Unknown $entityName: "$id"';
}

/// An operation that requires a `Check` to still be open (editable,
/// pre-submission) was attempted against one that has already been
/// submitted or cancelled.
final class CheckNotOpenViolation extends BusinessRuleViolation {
  const CheckNotOpenViolation({required this.checkId});

  final String checkId;

  @override
  String get description => 'Check "$checkId" is not open';
}

/// A `PackagePreparation` lifecycle transition that
/// `PackagePreparationTransitions.canTransition` does not permit was
/// attempted.
final class InvalidPackagePreparationTransitionViolation
    extends BusinessRuleViolation {
  const InvalidPackagePreparationTransitionViolation({
    required this.fromStatusName,
    required this.toStatusName,
  });

  final String fromStatusName;
  final String toStatusName;

  @override
  String get description =>
      'Invalid package preparation transition: $fromStatusName -> '
      '$toStatusName';
}

/// A `ChannelOperationalState` transition that
/// `ChannelOperationalStateTransitions.canTransition` does not permit was
/// attempted.
final class InvalidChannelOperationalStateTransitionViolation
    extends BusinessRuleViolation {
  const InvalidChannelOperationalStateTransitionViolation({
    required this.fromStateName,
    required this.toStateName,
  });

  final String fromStateName;
  final String toStateName;

  @override
  String get description =>
      'Invalid channel operational state transition: $fromStateName -> '
      '$toStateName';
}

/// A caller referenced a `CashDrawer`/`CashSession`/`CashMovement`/
/// `CashCount`/`CashReconciliation`/`CashAdjustment` id that does not
/// exist in the relevant repository (Phase 3 Sprint 3E).
final class UnknownCashEntityViolation extends BusinessRuleViolation {
  const UnknownCashEntityViolation({
    required this.entityName,
    required this.id,
  });

  final String entityName;
  final String id;

  @override
  String get description => 'Unknown $entityName: "$id"';
}

/// `OpenCashDrawer` was called for a drawer that already has a
/// non-closed `CashSession` — only one active session per drawer is ever
/// permitted.
final class CashSessionAlreadyActiveViolation extends BusinessRuleViolation {
  const CashSessionAlreadyActiveViolation({required this.drawerId});

  final String drawerId;

  @override
  String get description =>
      'Drawer "$drawerId" already has an active cash session';
}

/// A `CashMovement`/`CashCount` was attempted against a `CashSession`
/// that isn't `CashSessionStatus.active` — movements and new counts may
/// only be recorded while a session is actively being worked.
final class CashSessionNotActiveViolation extends BusinessRuleViolation {
  const CashSessionNotActiveViolation({
    required this.sessionId,
    required this.statusName,
  });

  final String sessionId;
  final String statusName;

  @override
  String get description =>
      'Cash session "$sessionId" is not active (status: $statusName)';
}

/// A `CashSession` transition that `CashSessionStatusTransitions
/// .canTransition` does not permit was attempted.
final class InvalidCashSessionTransitionViolation
    extends BusinessRuleViolation {
  const InvalidCashSessionTransitionViolation({
    required this.fromStatusName,
    required this.toStatusName,
  });

  final String fromStatusName;
  final String toStatusName;

  @override
  String get description =>
      'Invalid cash session transition: $fromStatusName -> $toStatusName';
}

/// A staff member attempted to approve/reject their own `CashCount` (as
/// a `CashReconciliation`) or their own requested `CashAdjustment` —
/// self-approval is never permitted, regardless of role.
final class SelfApprovalNotAllowedViolation extends BusinessRuleViolation {
  const SelfApprovalNotAllowedViolation({required this.staffId});

  final String staffId;

  @override
  String get description =>
      'Staff member "$staffId" cannot approve their own submission';
}

/// A caller referenced a `CourierSettlementSession`/`CourierCashCollection`/
/// `CourierCashDeclaration`/`CourierSettlement`/`CourierSettlementAdjustment`
/// id, or a `PaymentSession` id, that does not exist in the relevant
/// repository (Phase 3 Sprint 3F).
final class UnknownCourierSettlementEntityViolation
    extends BusinessRuleViolation {
  const UnknownCourierSettlementEntityViolation({
    required this.entityName,
    required this.id,
  });

  final String entityName;
  final String id;

  @override
  String get description => 'Unknown $entityName: "$id"';
}

/// `OpenCourierSettlementSession` was called for a courier that already
/// has a non-closed `CourierSettlementSession` — only one active
/// settlement session per courier is ever permitted.
final class CourierSettlementSessionAlreadyActiveViolation
    extends BusinessRuleViolation {
  const CourierSettlementSessionAlreadyActiveViolation({
    required this.courierId,
  });

  final String courierId;

  @override
  String get description =>
      'Courier "$courierId" already has an active settlement session';
}

/// A `CourierCashCollection`/`CourierCashDeclaration` was attempted
/// against a `CourierSettlementSession` that isn't in a status permitting
/// it.
final class CourierSettlementSessionNotActiveViolation
    extends BusinessRuleViolation {
  const CourierSettlementSessionNotActiveViolation({
    required this.sessionId,
    required this.statusName,
  });

  final String sessionId;
  final String statusName;

  @override
  String get description =>
      'Courier settlement session "$sessionId" is not active '
      '(status: $statusName)';
}

/// A `CourierSettlementSession` transition that
/// `CourierSettlementSessionStatusTransitions.canTransition` does not
/// permit was attempted.
final class InvalidCourierSettlementSessionTransitionViolation
    extends BusinessRuleViolation {
  const InvalidCourierSettlementSessionTransitionViolation({
    required this.fromStatusName,
    required this.toStatusName,
  });

  final String fromStatusName;
  final String toStatusName;

  @override
  String get description =>
      'Invalid courier settlement session transition: $fromStatusName -> '
      '$toStatusName';
}

/// A caller referenced a `KitchenWorkItem`/`KitchenEvent`/
/// `KitchenDisplayDevice`/`KitchenDisplaySession`/`KitchenRoutingRule` id
/// that does not exist in the relevant repository (Phase 4).
final class UnknownKdsEntityViolation extends BusinessRuleViolation {
  const UnknownKdsEntityViolation({
    required this.entityName,
    required this.id,
  });

  final String entityName;
  final String id;

  @override
  String get description => 'Unknown $entityName: "$id"';
}

/// A `KitchenLineStatus` transition that
/// `KitchenLineStatusTransitions.canTransition` does not permit was
/// attempted — including any attempt to silently move a completed
/// ([KitchenLineStatus.ready]) line back to an earlier state without
/// passing through [KitchenLineStatus.recalled] first.
final class InvalidKitchenLineTransitionViolation
    extends BusinessRuleViolation {
  const InvalidKitchenLineTransitionViolation({
    required this.fromStatusName,
    required this.toStatusName,
  });

  final String fromStatusName;
  final String toStatusName;

  @override
  String get description =>
      'Invalid kitchen line transition: $fromStatusName -> $toStatusName';
}

/// `KitchenEventRepository.append` was called with an `idempotencyKey`
/// already recorded for the branch — at-least-once delivery means a
/// caller may retry the same logical event; the repository rejects the
/// duplicate structurally rather than logging it twice. Callers that
/// expect retries should check `findByIdempotencyKey` first and treat an
/// existing match as success, not call `append` blindly.
final class DuplicateKitchenEventViolation extends BusinessRuleViolation {
  const DuplicateKitchenEventViolation({required this.idempotencyKey});

  final String idempotencyKey;

  @override
  String get description =>
      'Duplicate kitchen event idempotency key: "$idempotencyKey"';
}

/// A `KitchenWorkItem` (or other revisioned KDS record) transition was
/// attempted against a stale `expectedRevision` — the caller's view of the
/// record is out of date, most likely because another device already
/// acted on it. Prevents two devices from both completing the same line.
final class StaleKitchenRevisionViolation extends BusinessRuleViolation {
  const StaleKitchenRevisionViolation({
    required this.entityId,
    required this.expectedRevision,
    required this.actualRevision,
  });

  final String entityId;
  final int expectedRevision;
  final int actualRevision;

  @override
  String get description =>
      'Stale revision for "$entityId": expected $expectedRevision, actual '
      '$actualRevision';
}

/// `StartKitchenDisplaySession` was called for a device that already has
/// a non-ended `KitchenDisplaySession` — only one active session per
/// device is ever permitted.
final class KitchenDisplaySessionAlreadyActiveViolation
    extends BusinessRuleViolation {
  const KitchenDisplaySessionAlreadyActiveViolation({required this.deviceId});

  final String deviceId;

  @override
  String get description =>
      'Device "$deviceId" already has an active kitchen display session';
}

/// `CompleteKitchenOrderPreparation` was called for an order whose
/// `KitchenOrderView.isFullyReady` is still `false` — order-level
/// readiness is derived from its lines, never overridable by an explicit
/// "complete" call while a line remains unfinished.
final class KitchenOrderNotFullyReadyViolation extends BusinessRuleViolation {
  const KitchenOrderNotFullyReadyViolation({required this.orderId});

  final String orderId;

  @override
  String get description =>
      'Order "$orderId" kitchen preparation is not yet fully ready';
}

/// A caller referenced a `Courier`/`CourierShift`/`CourierAvailability`/
/// `Delivery`/`DeliveryAssignment`/`CourierDevice`/`CourierDeviceSession`
/// id that does not exist in the relevant repository (Phase 5).
final class UnknownCourierEntityViolation extends BusinessRuleViolation {
  const UnknownCourierEntityViolation({
    required this.entityName,
    required this.id,
  });

  final String entityName;
  final String id;

  @override
  String get description => 'Unknown $entityName: "$id"';
}

/// An action was attempted against a `Courier` whose
/// `CourierRegistryStatus` is not `active` (suspended/archived).
final class CourierRegistryNotActiveViolation extends BusinessRuleViolation {
  const CourierRegistryNotActiveViolation({
    required this.courierId,
    required this.statusName,
  });

  final String courierId;
  final String statusName;

  @override
  String get description =>
      'Courier "$courierId" is not active (status: $statusName)';
}

/// `RequestCourierShift` was called for a courier that already has a
/// non-terminal `CourierShift` — only one active shift per courier is
/// ever permitted.
final class CourierShiftAlreadyActiveViolation extends BusinessRuleViolation {
  const CourierShiftAlreadyActiveViolation({required this.courierId});

  final String courierId;

  @override
  String get description => 'Courier "$courierId" already has an active shift';
}

/// A `CourierShiftStatus` transition that
/// `CourierShiftStatusTransitions.canTransition` does not permit was
/// attempted.
final class InvalidCourierShiftTransitionViolation
    extends BusinessRuleViolation {
  const InvalidCourierShiftTransitionViolation({
    required this.fromStatusName,
    required this.toStatusName,
  });

  final String fromStatusName;
  final String toStatusName;

  @override
  String get description =>
      'Invalid courier shift transition: $fromStatusName -> $toStatusName';
}

/// `SetCourierAvailability` was called to reach
/// `CourierAvailabilityStatus.available` without an active, approved
/// `CourierShift` — "courier cannot become available without an active
/// approved shift."
final class CourierShiftRequiredViolation extends BusinessRuleViolation {
  const CourierShiftRequiredViolation({required this.courierId});

  final String courierId;

  @override
  String get description => 'Courier "$courierId" has no active approved shift';
}

/// A courier attempted to accept/act on a delivery while
/// `CourierAvailabilityStatus` is `offline`/`suspended`, or while at
/// capacity.
final class CourierNotAvailableViolation extends BusinessRuleViolation {
  const CourierNotAvailableViolation({
    required this.courierId,
    required this.reason,
  });

  final String courierId;
  final String reason;

  @override
  String get description => 'Courier "$courierId" is not available: $reason';
}

/// A `DeliveryStatus` transition that
/// `DeliveryStatusTransitions.canTransition` does not permit was
/// attempted.
final class InvalidDeliveryTransitionViolation extends BusinessRuleViolation {
  const InvalidDeliveryTransitionViolation({
    required this.fromStatusName,
    required this.toStatusName,
  });

  final String fromStatusName;
  final String toStatusName;

  @override
  String get description =>
      'Invalid delivery transition: $fromStatusName -> $toStatusName';
}

/// `ManuallyAssignDelivery`/`OfferDeliveryAssignment` was called for a
/// `Delivery` that already has an active accepted `DeliveryAssignment` —
/// "one delivery cannot have two active accepted couriers."
final class DeliveryAlreadyAssignedViolation extends BusinessRuleViolation {
  const DeliveryAlreadyAssignedViolation({required this.deliveryId});

  final String deliveryId;

  @override
  String get description =>
      'Delivery "$deliveryId" already has an active accepted courier';
}

/// `ConfirmPackagePickup` was called before the referenced
/// `PackagePreparation` reached a pickup-eligible status — "courier
/// cannot pick up an unprepared package."
final class PackageNotReadyForPickupViolation extends BusinessRuleViolation {
  const PackageNotReadyForPickupViolation({
    required this.deliveryId,
    required this.packageStatusName,
  });

  final String deliveryId;
  final String packageStatusName;

  @override
  String get description =>
      'Delivery "$deliveryId" package is not ready for pickup '
      '(status: $packageStatusName)';
}

/// A courier attempted to act on a `Delivery` they are not the currently
/// assigned courier for — "courier cannot complete a delivery they are
/// not assigned to."
final class DeliveryNotAssignedToCourierViolation
    extends BusinessRuleViolation {
  const DeliveryNotAssignedToCourierViolation({
    required this.deliveryId,
    required this.courierId,
  });

  final String deliveryId;
  final String courierId;

  @override
  String get description =>
      'Delivery "$deliveryId" is not assigned to courier "$courierId"';
}

/// A revisioned courier-domain record (`Delivery`/`CourierShift`/
/// `CourierAvailability`/`DeliveryAssignment`) transition was attempted
/// against a stale `expectedRevision`.
final class StaleCourierRevisionViolation extends BusinessRuleViolation {
  const StaleCourierRevisionViolation({
    required this.entityId,
    required this.expectedRevision,
    required this.actualRevision,
  });

  final String entityId;
  final int expectedRevision;
  final int actualRevision;

  @override
  String get description =>
      'Stale revision for "$entityId": expected $expectedRevision, actual '
      '$actualRevision';
}

/// `CourierEventRepository.append` was called with an `idempotencyKey`
/// already recorded for the branch.
final class DuplicateCourierEventViolation extends BusinessRuleViolation {
  const DuplicateCourierEventViolation({required this.idempotencyKey});

  final String idempotencyKey;

  @override
  String get description =>
      'Duplicate courier event idempotency key: "$idempotencyKey"';
}

/// A geofence-gated delivery action was attempted while
/// `GeofenceEvaluationResult.passesAutomatically` is `false` and no
/// `GeofenceOverride` was supplied — "geofence overrides require manager
/// authorization and reason."
final class GeofenceRequiresOverrideViolation extends BusinessRuleViolation {
  const GeofenceRequiresOverrideViolation({
    required this.deliveryId,
    required this.zoneTypeName,
  });

  final String deliveryId;
  final String zoneTypeName;

  @override
  String get description =>
      'Delivery "$deliveryId" geofence check for "$zoneTypeName" failed '
      'and requires a manager override';
}

/// `RecordCourierFeedback` was called with an empty tag list — "reuse
/// predefined feedback tags," which implies at least one must be chosen;
/// there is no untagged free-text feedback.
final class InvalidCourierFeedbackViolation extends BusinessRuleViolation {
  const InvalidCourierFeedbackViolation({required this.deliveryId});

  final String deliveryId;

  @override
  String get description =>
      'Delivery "$deliveryId" feedback requires at least one predefined tag';
}

/// A `DeliveryAssignment.status` transition (`offered` -> `accepted`/
/// `rejected`/`cancelled`, etc.) was attempted that the assignment's
/// current status does not permit — e.g. responding twice to the same
/// offer, or cancelling an already-accepted assignment.
final class InvalidDeliveryAssignmentTransitionViolation
    extends BusinessRuleViolation {
  const InvalidDeliveryAssignmentTransitionViolation({
    required this.fromStatusName,
    required this.toStatusName,
  });

  final String fromStatusName;
  final String toStatusName;

  @override
  String get description =>
      'Invalid delivery assignment transition: $fromStatusName -> '
      '$toStatusName';
}

/// `RespondToDeliveryAssignment` rejected an offer with a
/// `rejectionReasonCode` that is not one of the predefined
/// `CourierFeedbackTag` names — "courier rejection requires a predefined
/// reason tag," never free text.
final class InvalidAssignmentRejectionReasonViolation
    extends BusinessRuleViolation {
  const InvalidAssignmentRejectionReasonViolation({required this.reasonCode});

  final String reasonCode;

  @override
  String get description =>
      'Assignment rejection reason "$reasonCode" is not a predefined tag';
}

/// `ManuallyAssignDelivery`/`ReassignDelivery` was called with an empty
/// override reason — "manual override requires actor and reason," both
/// mandatory, never just one.
final class ManualOverrideReasonRequiredViolation
    extends BusinessRuleViolation {
  const ManualOverrideReasonRequiredViolation();

  @override
  String get description => 'A manual override requires a non-empty reason';
}

/// `CalculateDeliveryEarnings`/`CalculateShiftHourlyEarnings` was called
/// for a courier with no `CourierCompensationProfile` covering the
/// requested instant — earnings cannot be computed from an unconfigured
/// rate set (Sprint 5A).
final class NoEffectiveCompensationProfileViolation
    extends BusinessRuleViolation {
  const NoEffectiveCompensationProfileViolation({
    required this.courierId,
    required this.at,
  });

  final String courierId;
  final DateTime at;

  @override
  String get description =>
      'No compensation profile covers courier "$courierId" at $at';
}

/// A `CourierCompensationProfile`/`CourierShiftSchedule` was constructed
/// with an invalid shape — a negative rate/distance value, `effectiveUntil`
/// not strictly after `effectiveFrom`, or `scheduledEnd` not strictly
/// after `scheduledStart` (Sprint 5A).
final class InvalidCompensationConfigurationViolation
    extends BusinessRuleViolation {
  const InvalidCompensationConfigurationViolation({required this.reason});

  final String reason;

  @override
  String get description => 'Invalid compensation profile: $reason';
}

/// `CalculateDeliveryEarnings` was called for a `Delivery` that is neither
/// `delivered` nor a manager-approved `cancelled` — "cancelled deliveries
/// do not generate package earnings unless manager-approved" (Sprint 5A).
final class DeliveryNotEligibleForEarningsViolation
    extends BusinessRuleViolation {
  const DeliveryNotEligibleForEarningsViolation({
    required this.deliveryId,
    required this.statusName,
  });

  final String deliveryId;
  final String statusName;

  @override
  String get description =>
      'Delivery "$deliveryId" is not eligible for package earnings '
      '(status: $statusName)';
}

/// `MarkCourierEarningsPaid` referenced an earnings/adjustment id that
/// already appears in an earlier `CourierEarningsPayment` — "locked
/// earnings become immutable," paying the same record twice is rejected
/// structurally (Sprint 5A).
final class EarningsAlreadyPaidViolation extends BusinessRuleViolation {
  const EarningsAlreadyPaidViolation({required this.earningsId});

  final String earningsId;

  @override
  String get description => 'Earnings record "$earningsId" was already paid';
}

/// A courier attempted a state-changing operational action (shift
/// activation, becoming available, accepting an assignment, package
/// pickup, delivery progression, or completion) while their latest
/// `CourierLocationAvailability` is `unavailable` and no active
/// `LocationEmergencyOverride` covers the action — "a courier must not be
/// operationally usable without location access during an active shift"
/// (Sprint 5B REQUIRED business-rule correction).
final class LocationUnavailableViolation extends BusinessRuleViolation {
  const LocationUnavailableViolation({
    required this.courierId,
    this.reasonName,
  });

  final String courierId;
  final String? reasonName;

  @override
  String get description => 'Courier "$courierId" has no available location'
      '${reasonName == null ? '' : ' ($reasonName)'} — action blocked';
}

/// A manager-submitted `CourierDeliverySequence` reorder did not exactly
/// match the courier's current set of active (non-terminal) deliveries —
/// either a delivery was added/removed/duplicated, or a completed
/// delivery was included ("completed deliveries cannot move") — Sprint
/// 5C Part 5.
final class InvalidDeliverySequenceViolation extends BusinessRuleViolation {
  const InvalidDeliverySequenceViolation({
    required this.courierId,
    required this.expectedDeliveryIds,
    required this.submittedDeliveryIds,
  });

  final String courierId;
  final List<String> expectedDeliveryIds;
  final List<String> submittedDeliveryIds;

  @override
  String get description =>
      'Submitted delivery sequence for courier "$courierId" '
      '($submittedDeliveryIds) does not match their active deliveries '
      '($expectedDeliveryIds)';
}

/// A `SameDestinationGroup` was submitted with fewer than two deliveries
/// — "same destination" is meaningless for a single delivery (Sprint 5C
/// Part 6).
final class SameDestinationGroupTooSmallViolation
    extends BusinessRuleViolation {
  const SameDestinationGroupTooSmallViolation({required this.deliveryCount});

  final int deliveryCount;

  @override
  String get description =>
      'A same-destination group requires at least 2 deliveries, got '
      '$deliveryCount';
}

/// A [CourierMessageType.direct] message was sent without a
/// `recipientCourierId`, or a [CourierMessageType.broadcast]/
/// [CourierMessageType.emergency] message was sent *with* one — Sprint 5C
/// Part 8's Communication Center.
final class InvalidCourierMessageRecipientViolation
    extends BusinessRuleViolation {
  const InvalidCourierMessageRecipientViolation({required this.typeName});

  final String typeName;

  @override
  String get description => 'Invalid recipient for a "$typeName" message';
}

/// An acknowledgement was attempted for a [CourierMessage] whose
/// [CourierMessage.type] is not [CourierMessageType.emergency] — only
/// emergency messages require/accept acknowledgement (Sprint 5C Part 8).
/// Also thrown by `RecordCourierMessageStatus` if called with
/// `CourierMessageStatusEventType.acknowledged` directly — acknowledgement
/// only ever goes through `AcknowledgeEmergencyMessage`'s own validation.
final class MessageAcknowledgementNotRequiredViolation
    extends BusinessRuleViolation {
  const MessageAcknowledgementNotRequiredViolation({required this.messageId});

  final String messageId;

  @override
  String get description =>
      'Message "$messageId" is not an emergency message and does not '
      'accept acknowledgement';
}

/// A caller referenced a `Customer`/`VisitRewardRule`/`Survey`/
/// `CustomerNotificationCampaign`/`CustomerFeedback` id (or any other
/// Sprint 5D CRM/Feedback entity) that does not exist in the relevant
/// repository — the CRM/Feedback-feature sibling of
/// `UnknownCourierEntityViolation`, kept separate rather than reused
/// since that type's own doc comment scopes it to courier-domain entities
/// only (Sprint 5D).
final class UnknownCrmEntityViolation extends BusinessRuleViolation {
  const UnknownCrmEntityViolation({
    required this.entityName,
    required this.id,
  });

  final String entityName;
  final String id;

  @override
  String get description => 'Unknown $entityName: "$id"';
}

/// A `VisitRewardRule` was created/edited with an invalid configuration
/// (e.g. a non-positive `requiredVisitCount`) — Sprint 5D's Visit Rewards
/// Engine.
final class InvalidVisitRewardRuleViolation extends BusinessRuleViolation {
  const InvalidVisitRewardRuleViolation({required this.reason});

  final String reason;

  @override
  String get description => 'Invalid visit reward rule: $reason';
}

/// A `Survey` was created with an invalid shape (no questions, a
/// `multipleChoice` question with fewer than 2 options, or duplicate
/// question ids) — Sprint 5D's Survey Engine.
final class InvalidSurveyViolation extends BusinessRuleViolation {
  const InvalidSurveyViolation({required this.reason});

  final String reason;

  @override
  String get description => 'Invalid survey: $reason';
}

/// A `SurveyResponse` was submitted that doesn't answer exactly the
/// target survey's questions, or an answer's shape doesn't match its
/// question's `SurveyQuestionType` (e.g. no `numericValue` for a rating
/// question, an out-of-range value, an unknown `multipleChoice` option
/// id) — Sprint 5D's Survey Engine.
final class InvalidSurveyResponseViolation extends BusinessRuleViolation {
  const InvalidSurveyResponseViolation({required this.reason});

  final String reason;

  @override
  String get description => 'Invalid survey response: $reason';
}

/// A `CustomerNotificationCampaign` status transition was attempted that
/// its current status does not allow (e.g. scheduling a campaign that
/// isn't a `draft`) — Sprint 5D's CRM Notification Foundation.
final class InvalidNotificationCampaignTransitionViolation
    extends BusinessRuleViolation {
  const InvalidNotificationCampaignTransitionViolation({
    required this.campaignId,
    required this.fromStatusName,
  });

  final String campaignId;
  final String fromStatusName;

  @override
  String get description =>
      'Cannot schedule campaign "$campaignId" from status '
      '"$fromStatusName" — only a draft campaign may be scheduled';
}

/// A `CustomerFeedback` submission had an empty subject or body — Sprint
/// 5D's Customer Feedback Center.
final class InvalidCustomerFeedbackViolation extends BusinessRuleViolation {
  const InvalidCustomerFeedbackViolation({required this.reason});

  final String reason;

  @override
  String get description => 'Invalid customer feedback: $reason';
}

/// A `StaffMember`/`Organization`/`Restaurant`/`Branch`/`CustomerPhoto`/
/// device-registry id (or any other Phase 6 Admin Platform entity) that
/// does not exist in the relevant repository — the Admin Platform
/// sibling of `UnknownCourierEntityViolation`/`UnknownCrmEntityViolation`,
/// kept separate for the same reason those two are (`docs/decisions.md`
/// ADR-023).
final class UnknownAdminEntityViolation extends BusinessRuleViolation {
  const UnknownAdminEntityViolation({
    required this.entityName,
    required this.id,
  });

  final String entityName;
  final String id;

  @override
  String get description => 'Unknown $entityName: "$id"';
}

/// A staff member attempted to grant a role to themselves — "no
/// self-promotion," enforced structurally regardless of what
/// `PosAuthorizationPolicy` would otherwise allow (Phase 6C,
/// `docs/decisions.md` ADR-023).
final class SelfRoleGrantNotAllowedViolation extends BusinessRuleViolation {
  const SelfRoleGrantNotAllowedViolation({required this.staffMemberId});

  final String staffMemberId;

  @override
  String get description =>
      'Staff member "$staffMemberId" cannot grant a role to themselves';
}

/// A [StaffMember] action was attempted while the member's
/// `StaffMemberStatus` is `suspended` or `archived` — "suspended actor
/// cannot create a valid operational session," extended to every
/// mutating staff-admin action, not just sign-in (Phase 6C,
/// `docs/decisions.md` ADR-023).
final class StaffMemberNotActiveViolation extends BusinessRuleViolation {
  const StaffMemberNotActiveViolation({required this.staffMemberId});

  final String staffMemberId;

  @override
  String get description => 'Staff member "$staffMemberId" is not active';
}

/// Thrown by `BootstrapFirstAdminAccount` when at least one `StaffMember`
/// already exists — bootstrapping only ever runs once (Phase 6B,
/// `docs/decisions.md` ADR-023).
final class AdminPlatformAlreadyBootstrappedViolation
    extends BusinessRuleViolation {
  const AdminPlatformAlreadyBootstrappedViolation();

  @override
  String get description =>
      'The Admin Platform already has at least one staff member — '
      'bootstrapping only runs once';
}

/// An `archived` `Branch` was targeted by a status change — `archived`
/// is terminal, same reasoning as `StaffMemberArchivedViolation` (Phase
/// 6D, `docs/decisions.md` ADR-023).
final class BranchArchivedViolation extends BusinessRuleViolation {
  const BranchArchivedViolation({required this.branchId});

  final String branchId;

  @override
  String get description =>
      'Branch "$branchId" is archived and cannot be changed';
}

/// An `archived` [StaffMember] was targeted by a status change —
/// `archived` is terminal, mirroring `CourierShift`'s own reversible-
/// vs-terminal state distinction (Phase 6C, `docs/decisions.md`
/// ADR-023).
final class StaffMemberArchivedViolation extends BusinessRuleViolation {
  const StaffMemberArchivedViolation({required this.staffMemberId});

  final String staffMemberId;

  @override
  String get description =>
      'Staff member "$staffMemberId" is archived and cannot be changed';
}
