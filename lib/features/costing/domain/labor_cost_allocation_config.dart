import '../../../shared/models/money.dart';

/// Foundation only — "LaborCostAllocation foundation" from the brief.
/// Stores a branch's configured hourly labor rate; no calculation
/// engine consumes this yet this phase (full labor-cost allocation —
/// distributing staff hours/wages across orders/portions — is
/// deliberately out of scope, matching the kickoff's own "full
/// workforce/payroll allocation" exclusion). Phase 7
/// (`docs/decisions.md` ADR-024).
class LaborCostAllocationConfig {
  const LaborCostAllocationConfig({
    required this.id,
    required this.organizationId,
    required this.branchId,
    required this.hourlyRate,
    required this.effectiveFrom,
    required this.createdAt,
  });

  final String id;
  final String organizationId;
  final String branchId;
  final Money hourlyRate;
  final DateTime effectiveFrom;
  final DateTime createdAt;
}
