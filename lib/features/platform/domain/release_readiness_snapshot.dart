import '../../../bootstrap/app_environment.dart';
import 'release_readiness_criterion.dart';
import 'release_readiness_criterion_status.dart';

/// A build's release-readiness checklist — Phase 8P
/// (`docs/decisions.md` ADR-025), "Release Readiness Foundation."
/// Purely a readiness *record*: it never publishes anything and has no
/// relationship to any store submission API. Mirrors
/// `PlatformMonitoringSnapshot`'s "real, computed-fresh, honestly
/// reported" shape one level over — this is the release/build-process
/// axis, `StoreComplianceSnapshot` (8Q) is the store-policy axis.
class ReleaseReadinessSnapshot {
  const ReleaseReadinessSnapshot({
    required this.environment,
    required this.criteria,
    required this.generatedAt,
  });

  final AppEnvironment environment;
  final List<ReleaseReadinessCriterion> criteria;
  final DateTime generatedAt;

  /// True only when every criterion is genuinely [ReleaseReadinessCriterionStatus.ready] —
  /// a [ReleaseReadinessCriterionStatus.manualStepRequired] item still
  /// blocks this, since it is not yet actually done.
  bool get isReleaseReady => criteria.every(
        (criterion) =>
            criterion.status == ReleaseReadinessCriterionStatus.ready,
      );

  List<ReleaseReadinessCriterion> get blockingCriteria => criteria
      .where((criterion) =>
          criterion.status != ReleaseReadinessCriterionStatus.ready)
      .toList(growable: false);
}
