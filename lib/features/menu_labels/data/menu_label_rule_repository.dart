import '../domain/menu_label_rule.dart';
import '../domain/menu_label_type.dart';

abstract interface class MenuLabelRuleRepository {
  Future<void> save(MenuLabelRule rule);
  Future<List<MenuLabelRule>> findActiveByLabelType(MenuLabelType labelType);
  Future<List<MenuLabelRule>> findAllActive();
}

class InMemoryMenuLabelRuleRepository implements MenuLabelRuleRepository {
  final List<MenuLabelRule> _rules = [];

  @override
  Future<void> save(MenuLabelRule rule) async {
    _rules.add(rule);
  }

  @override
  Future<List<MenuLabelRule>> findActiveByLabelType(
      MenuLabelType labelType) async {
    return List.unmodifiable(
      _rules.where((r) => r.labelType == labelType && r.isActive),
    );
  }

  @override
  Future<List<MenuLabelRule>> findAllActive() async {
    return List.unmodifiable(_rules.where((r) => r.isActive));
  }
}
