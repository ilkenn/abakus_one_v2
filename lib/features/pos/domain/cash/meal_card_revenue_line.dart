/// One meal-card brand's share of a cash session's revenue (2026-11-11,
/// product owner: Pluxee / Multinet / Setcard / Edenred each get their own
/// Z-Raporu line for cash-up and provider reconciliation, never folded into
/// "Diğer"). Server-computed by `getDailyRevenueSummary`'s
/// `mealCardBreakdown`; the four POS brands are always present, even at 0.
class MealCardRevenueLine {
  const MealCardRevenueLine({
    required this.paymentMethodId,
    required this.displayName,
    required this.amountMinorUnits,
  });

  /// Payment-method catalog id, e.g. `multinet`.
  final String paymentMethodId;

  /// Shown on the report, e.g. "Multinet".
  final String displayName;
  final int amountMinorUnits;

  factory MealCardRevenueLine.fromWire(Map<String, dynamic> data) {
    return MealCardRevenueLine(
      paymentMethodId: data['paymentMethodId'] as String,
      displayName: data['displayName'] as String,
      amountMinorUnits: data['amountMinorUnits'] as int,
    );
  }
}
