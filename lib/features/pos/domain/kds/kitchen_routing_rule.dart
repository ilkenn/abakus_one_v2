import 'kitchen_station.dart';

/// What a [KitchenRoutingRule] matches against — every non-null field must
/// match (AND-combined) for the rule to apply. All fields optional so a
/// rule can be as broad or narrow as needed; a rule with every field
/// `null` matches everything (a catch-all).
class KitchenRoutingCriteria {
  const KitchenRoutingCriteria({
    this.productId,
    this.categoryId,
    this.modifierCode,
    this.channelName,
  });

  final String? productId;
  final String? categoryId;
  final String? modifierCode;

  /// `OrderChannel.name` — carried as a raw string, not the `orders`-
  /// feature enum itself, so this domain model (in `pos`) never depends on
  /// `orders`' presentation-adjacent types beyond what it already imports
  /// elsewhere (mirrors how `BusinessRuleViolation` carries enum values as
  /// `.name` strings rather than typed feature enums).
  final String? channelName;

  bool matches({
    String? productId,
    String? categoryId,
    Set<String> modifierCodes = const {},
    String? channelName,
  }) {
    if (this.productId != null && this.productId != productId) return false;
    if (this.categoryId != null && this.categoryId != categoryId) {
      return false;
    }
    if (modifierCode != null && !modifierCodes.contains(modifierCode)) {
      return false;
    }
    if (this.channelName != null && this.channelName != channelName) {
      return false;
    }
    return true;
  }
}

/// One branch-scoped, deterministic, ordered routing rule — evaluated in
/// ascending [priority] order; the first matching rule wins. No rule
/// editor UI exists this phase (deliberately out of scope) — rules are
/// currently constructed/seeded programmatically only.
class KitchenRoutingRule {
  const KitchenRoutingRule({
    required this.id,
    required this.branchId,
    required this.priority,
    required this.criteria,
    required this.targetStation,
  });

  final String id;
  final String branchId;

  /// Lower evaluates first. Rules must have distinct priorities within a
  /// branch for genuinely deterministic ordering — `KitchenRoutingResolver`
  /// sorts by this value, ties broken by list order as supplied.
  final int priority;

  final KitchenRoutingCriteria criteria;
  final KitchenStation targetStation;
}
