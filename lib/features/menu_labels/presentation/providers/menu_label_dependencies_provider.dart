import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/identity/menu_label_rule_id_generator.dart';
import '../../application/identity/menu_label_suggestion_id_generator.dart';
import '../../data/menu_label_audit_entry_repository.dart';
import '../../data/menu_label_rule_repository.dart';
import '../../data/menu_label_suggestion_repository.dart';

/// Central Riverpod wiring for `features/menu_labels` — Phase 7
/// (`docs/decisions.md` ADR-024). Repository/id-generator providers
/// only, matching the pattern established across every other Phase 7
/// feature — no pre-wired, authorization-policy-baked use-case
/// providers.
final menuLabelRuleRepositoryProvider =
    Provider<MenuLabelRuleRepository>((ref) {
  return InMemoryMenuLabelRuleRepository();
});

final menuLabelRuleIdGeneratorProvider =
    Provider<MenuLabelRuleIdGenerator>((ref) {
  return SequentialMenuLabelRuleIdGenerator();
});

final menuLabelSuggestionRepositoryProvider =
    Provider<MenuLabelSuggestionRepository>((ref) {
  return InMemoryMenuLabelSuggestionRepository();
});

final menuLabelSuggestionIdGeneratorProvider =
    Provider<MenuLabelSuggestionIdGenerator>((ref) {
  return SequentialMenuLabelSuggestionIdGenerator();
});

final menuLabelAuditEntryRepositoryProvider =
    Provider<MenuLabelAuditEntryRepository>((ref) {
  return InMemoryMenuLabelAuditEntryRepository();
});
