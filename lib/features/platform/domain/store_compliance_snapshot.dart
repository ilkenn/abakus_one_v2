import 'store_compliance_criterion.dart';
import 'store_compliance_criterion_status.dart';

/// A cross-platform (Apple App Store + Google Play) store-policy
/// compliance checklist — Phase 8Q (`docs/decisions.md` ADR-025),
/// "Store Compliance Foundation." Purely a readiness *record*: it
/// never submits or publishes anything to any store. Mirrors
/// `ReleaseReadinessSnapshot`'s "real, honestly reported checklist"
/// shape — that snapshot is the release/build-process axis, this one
/// is the store-policy axis (account deletion, data export, privacy
/// policy, data-safety declarations).
class StoreComplianceSnapshot {
  const StoreComplianceSnapshot({
    required this.criteria,
    required this.generatedAt,
  });

  final List<StoreComplianceCriterion> criteria;
  final DateTime generatedAt;

  /// True only when every criterion is genuinely
  /// [StoreComplianceCriterionStatus.ready] — a
  /// [StoreComplianceCriterionStatus.manualStepRequired] item still
  /// blocks this, since it is not yet actually done.
  bool get isStoreCompliant => criteria.every(
        (criterion) => criterion.status == StoreComplianceCriterionStatus.ready,
      );

  List<StoreComplianceCriterion> get blockingCriteria => criteria
      .where((criterion) =>
          criterion.status != StoreComplianceCriterionStatus.ready)
      .toList(growable: false);
}
