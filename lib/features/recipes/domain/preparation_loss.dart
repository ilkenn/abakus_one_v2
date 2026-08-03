/// Weight/volume lost during raw preparation (peeling, trimming,
/// deboning) before cooking begins — Phase 7 (`docs/decisions.md`
/// ADR-024). Expressed as [lossBasisPoints] (0-10000, i.e. hundredths
/// of a percent) rather than a `double` percentage — the same
/// exact-integer discipline `Money`/`Quantity` already follow, since
/// this value feeds directly into yield/cost calculations.
class PreparationLoss {
  const PreparationLoss({required this.lossBasisPoints, this.description});

  /// 0 = no loss, 10000 = 100% loss (nothing usable remains).
  final int lossBasisPoints;
  final String? description;
}
