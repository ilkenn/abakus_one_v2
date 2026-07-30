import '../domain/rewards/visit_reward_rule.dart';

/// Storage for [VisitRewardRule] — mutable registry entity (mirrors
/// `CourierRepository`), since "active/inactive" and campaign-date edits
/// are in-place administrator edits to a rule's own current shape, not
/// an append-only operational log.
abstract interface class VisitRewardRuleRepository {
  Future<void> save(VisitRewardRule rule);
  Future<VisitRewardRule?> findById(String ruleId);
  Future<List<VisitRewardRule>> findAll();
}

class InMemoryVisitRewardRuleRepository implements VisitRewardRuleRepository {
  final Map<String, VisitRewardRule> _byId = {};

  @override
  Future<void> save(VisitRewardRule rule) async => _byId[rule.id] = rule;

  @override
  Future<VisitRewardRule?> findById(String ruleId) async => _byId[ruleId];

  @override
  Future<List<VisitRewardRule>> findAll() async {
    return List.unmodifiable(_byId.values);
  }
}
