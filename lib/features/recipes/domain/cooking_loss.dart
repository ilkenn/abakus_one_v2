/// Weight/volume lost during cooking (evaporation, rendering) — Phase
/// 7 (`docs/decisions.md` ADR-024). See [PreparationLoss] for why this
/// is [lossBasisPoints], not a `double`.
class CookingLoss {
  const CookingLoss({required this.lossBasisPoints, this.description});

  /// 0 = no loss, 10000 = 100% loss (nothing usable remains).
  final int lossBasisPoints;
  final String? description;
}
