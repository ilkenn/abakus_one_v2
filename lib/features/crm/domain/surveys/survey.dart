import '../segmentation/customer.dart';
import '../segmentation/customer_category.dart';
import 'survey_question.dart';

/// An administrator-authored survey — Sprint 5D's Survey Engine. A
/// mutable registry entity (mirrors `VisitRewardRule`'s own shape): an
/// administrator edits a survey's own current shape in place;
/// [revision] is an optimistic-concurrency counter, not a preserved
/// history. Already-submitted `SurveyResponse`s are unaffected by a later
/// edit — they only ever reference `questionId`s, never a snapshot of
/// question text.
class Survey {
  const Survey({
    required this.id,
    required this.title,
    required this.questions,
    this.targetCategory,
    this.optionalRewardRuleId,
    required this.activeFrom,
    this.activeUntil,
    this.isActive = true,
    required this.createdByStaffId,
    required this.createdAt,
    required this.revision,
  });

  final String id;
  final String title;
  final List<SurveyQuestion> questions;

  /// `null` means "every customer" — targeting is optional, mirroring
  /// [Customer.category] itself being optional.
  final CustomerCategory? targetCategory;

  /// References a `VisitRewardRule.id` — "optional reward." `null` when
  /// this survey grants nothing.
  final String? optionalRewardRuleId;

  final DateTime activeFrom;
  final DateTime? activeUntil;
  final bool isActive;

  final String createdByStaffId;
  final DateTime createdAt;
  final int revision;

  bool isCurrentlyActive(DateTime now) {
    if (!isActive) return false;
    if (now.isBefore(activeFrom)) return false;
    final until = activeUntil;
    if (until != null && now.isAfter(until)) return false;
    return true;
  }

  /// Whether [customer] is in this survey's target audience — always
  /// `true` when [targetCategory] is `null`.
  bool targetsCustomer(Customer customer) =>
      targetCategory == null || customer.category == targetCategory;

  Survey copyWith({
    String? title,
    List<SurveyQuestion>? questions,
    CustomerCategory? targetCategory,
    bool clearTargetCategory = false,
    String? optionalRewardRuleId,
    bool clearOptionalRewardRuleId = false,
    DateTime? activeFrom,
    DateTime? activeUntil,
    bool clearActiveUntil = false,
    bool? isActive,
    required int revision,
  }) {
    return Survey(
      id: id,
      title: title ?? this.title,
      questions: questions ?? this.questions,
      targetCategory:
          clearTargetCategory ? null : (targetCategory ?? this.targetCategory),
      optionalRewardRuleId: clearOptionalRewardRuleId
          ? null
          : (optionalRewardRuleId ?? this.optionalRewardRuleId),
      activeFrom: activeFrom ?? this.activeFrom,
      activeUntil: clearActiveUntil ? null : (activeUntil ?? this.activeUntil),
      isActive: isActive ?? this.isActive,
      createdByStaffId: createdByStaffId,
      createdAt: createdAt,
      revision: revision,
    );
  }
}
