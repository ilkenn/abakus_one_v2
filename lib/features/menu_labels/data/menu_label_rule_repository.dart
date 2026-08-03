import '../domain/menu_label_rule.dart';
import '../domain/menu_label_type.dart';

abstract interface class MenuLabelRuleRepository {
  Future<void> save(MenuLabelRule rule);
  Future<List<MenuLabelRule>> findActiveByLabelType(
      String organizationId, MenuLabelType labelType);
  Future<List<MenuLabelRule>> findAllActive(String organizationId);
}

class InMemoryMenuLabelRuleRepository implements MenuLabelRuleRepository {
  final List<MenuLabelRule> _rules = [];

  @override
  Future<void> save(MenuLabelRule rule) async {
    _rules.add(rule);
  }

  @override
  Future<List<MenuLabelRule>> findActiveByLabelType(
      String organizationId, MenuLabelType labelType) async {
    return List.unmodifiable(
      _rules.where((r) =>
          r.organizationId == organizationId &&
          r.labelType == labelType &&
          r.isActive),
    );
  }

  @override
  Future<List<MenuLabelRule>> findAllActive(String organizationId) async {
    return List.unmodifiable(
      _rules.where((r) => r.organizationId == organizationId && r.isActive),
    );
  }
}
