import '../../../shared/models/money.dart';

enum OverheadAllocationBasis { perOrder, perPortion }

/// Foundation only — "OverheadAllocation foundation" from the brief.
/// Stores a branch's configured monthly overhead figure and intended
/// allocation basis; no calculation engine consumes this yet this
/// phase. Phase 7 (`docs/decisions.md` ADR-024).
class OverheadAllocationConfig {
  const OverheadAllocationConfig({
    required this.id,
    required this.organizationId,
    required this.branchId,
    required this.monthlyOverhead,
    required this.allocationBasis,
    required this.effectiveFrom,
    required this.createdAt,
  });

  final String id;
  final String organizationId;
  final String branchId;
  final Money monthlyOverhead;
  final OverheadAllocationBasis allocationBasis;
  final DateTime effectiveFrom;
  final DateTime createdAt;
}
