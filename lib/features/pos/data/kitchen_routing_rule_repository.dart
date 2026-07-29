import '../domain/kds/kitchen_routing_rule.dart';

/// Storage for [KitchenRoutingRule]s — mutable registry, branch-scoped.
/// No rule editor UI exists this phase; rules are seeded/managed
/// programmatically only.
abstract interface class KitchenRoutingRuleRepository {
  Future<void> save(KitchenRoutingRule rule);

  /// Every rule for [branchId], in no particular order —
  /// `KitchenRoutingResolver.resolve` sorts by priority itself.
  Future<List<KitchenRoutingRule>> findByBranchId(String branchId);
}

/// In-memory [KitchenRoutingRuleRepository] — the only implementation
/// this phase.
class InMemoryKitchenRoutingRuleRepository
    implements KitchenRoutingRuleRepository {
  final Map<String, KitchenRoutingRule> _rulesById = {};

  @override
  Future<void> save(KitchenRoutingRule rule) async {
    _rulesById[rule.id] = rule;
  }

  @override
  Future<List<KitchenRoutingRule>> findByBranchId(String branchId) async {
    return List.unmodifiable(
      _rulesById.values.where((r) => r.branchId == branchId),
    );
  }
}
