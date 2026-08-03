import 'menu_label_type.dart';

/// One system-generated, rule-driven label suggestion for a specific
/// `Recipe`/`RecipeVersion` — Phase 7 (`docs/decisions.md` ADR-024).
/// [isApproved] always starts `false` — "system-generated marked
/// suggested until approved" — the only way it becomes `true` is
/// `ApproveMenuLabelSuggestion`, a distinct human action.
class MenuLabelSuggestion {
  const MenuLabelSuggestion({
    required this.id,
    required this.recipeId,
    required this.recipeVersionId,
    required this.labelType,
    required this.ruleId,
    required this.ruleVersion,
    required this.evidenceSummary,
    required this.isApproved,
    this.approvedByStaffId,
    this.approvedAt,
    required this.createdAt,
  });

  final String id;
  final String recipeId;
  final String recipeVersionId;
  final MenuLabelType labelType;
  final String ruleId;
  final int ruleVersion;

  /// Human-readable statement of exactly what evidence made this
  /// label qualify (e.g. "35000mg protein/portion >= 25000mg
  /// threshold") — never a bare boolean, so an approving manager can
  /// see why the system suggested it.
  final String evidenceSummary;

  final bool isApproved;
  final String? approvedByStaffId;
  final DateTime? approvedAt;
  final DateTime createdAt;

  MenuLabelSuggestion copyWith({
    bool? isApproved,
    String? approvedByStaffId,
    DateTime? approvedAt,
  }) {
    return MenuLabelSuggestion(
      id: id,
      recipeId: recipeId,
      recipeVersionId: recipeVersionId,
      labelType: labelType,
      ruleId: ruleId,
      ruleVersion: ruleVersion,
      evidenceSummary: evidenceSummary,
      isApproved: isApproved ?? this.isApproved,
      approvedByStaffId: approvedByStaffId ?? this.approvedByStaffId,
      approvedAt: approvedAt ?? this.approvedAt,
      createdAt: createdAt,
    );
  }
}
