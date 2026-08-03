import '../../../shared/models/money.dart';

/// A reusable packaging item's unit cost (a box, a bag, a cup) — Phase
/// 7 (`docs/decisions.md` ADR-024). Reference data only this phase —
/// composed into a product's total cost by 7N's Profitability Engine,
/// not by `CalculateRecipeCost` itself (a recipe's ingredient cost and
/// its packaging cost are conceptually separate contributions).
class PackagingCost {
  const PackagingCost({
    required this.id,
    required this.organizationId,
    required this.name,
    required this.unitCost,
    required this.createdAt,
  });

  final String id;
  final String organizationId;
  final String name;
  final Money unitCost;
  final DateTime createdAt;
}
