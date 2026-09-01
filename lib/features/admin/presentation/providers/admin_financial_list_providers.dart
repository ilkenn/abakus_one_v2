import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/financial/admin_financial_summaries.dart';
import 'admin_dependencies_provider.dart';
import 'admin_financial_dependencies_provider.dart';
import '../../../navigation/presentation/providers/current_branch_provider.dart';

/// AP-4 Wave D — Admin's branch-wide financial list providers. Each
/// re-fetches on every `ref.watch`/`ref.refresh` (no `.snapshots()`
/// listener, matching `adminFinancialView.ts`'s own doc comment: a
/// bounded, permission-gated callable, not a live stream) — mirrors
/// [adminReservationListProvider]'s exact `FutureProvider.family` shape.
///
/// `organizationId`/`branchId` are resolved from [currentOrganizationIdProvider]/
/// [currentBranchIdProvider] inside each provider body (never baked into
/// the family argument) so switching branch/org context automatically
/// invalidates every one of these via their own `ref.watch`.

final adminPaymentSessionsProvider =
    FutureProvider.family<List<AdminPaymentSessionSummary>, int>(
        (ref, pageSize) {
  final gateway = ref.watch(adminFinancialGatewayProvider);
  final organizationId = ref.watch(currentOrganizationIdProvider);
  final branchId = ref.watch(currentBranchIdProvider);
  return gateway.listPaymentSessionsForBranch(
    organizationId: organizationId,
    branchId: branchId,
    pageSize: pageSize,
  );
});

final adminRefundsProvider =
    FutureProvider.family<List<AdminRefundSummary>, int>((ref, pageSize) {
  final gateway = ref.watch(adminFinancialGatewayProvider);
  final organizationId = ref.watch(currentOrganizationIdProvider);
  final branchId = ref.watch(currentBranchIdProvider);
  return gateway.listRefundsForBranch(
    organizationId: organizationId,
    branchId: branchId,
    pageSize: pageSize,
  );
});

final adminCashSessionsProvider =
    FutureProvider.family<List<AdminCashSessionSummary>, int>((ref, pageSize) {
  final gateway = ref.watch(adminFinancialGatewayProvider);
  final organizationId = ref.watch(currentOrganizationIdProvider);
  final branchId = ref.watch(currentBranchIdProvider);
  return gateway.listCashSessionsForBranch(
    organizationId: organizationId,
    branchId: branchId,
    pageSize: pageSize,
  );
});

/// [onlyUnresolved] true = the reconciliation-queue view (only
/// `unknownReconciliationRequired`/`manualInterventionRequired` entries).
class AdminFiscalJournalQuery {
  const AdminFiscalJournalQuery(
      {this.onlyUnresolved = false, this.pageSize = 50});
  final bool onlyUnresolved;
  final int pageSize;

  @override
  bool operator ==(Object other) =>
      other is AdminFiscalJournalQuery &&
      other.onlyUnresolved == onlyUnresolved &&
      other.pageSize == pageSize;

  @override
  int get hashCode => Object.hash(onlyUnresolved, pageSize);
}

final adminFiscalOperationsProvider = FutureProvider.family<
    List<AdminFiscalOperationSummary>, AdminFiscalJournalQuery>((ref, query) {
  final gateway = ref.watch(adminFinancialGatewayProvider);
  final organizationId = ref.watch(currentOrganizationIdProvider);
  final branchId = ref.watch(currentBranchIdProvider);
  return gateway.listFiscalOperationsForBranch(
    organizationId: organizationId,
    branchId: branchId,
    onlyUnresolved: query.onlyUnresolved,
    pageSize: query.pageSize,
  );
});

final adminOfflineLeasesProvider =
    FutureProvider.family<List<AdminOfflineLeaseSummary>, int>((ref, pageSize) {
  final gateway = ref.watch(adminFinancialGatewayProvider);
  final organizationId = ref.watch(currentOrganizationIdProvider);
  final branchId = ref.watch(currentBranchIdProvider);
  return gateway.listOfflineLeasesForBranch(
    organizationId: organizationId,
    branchId: branchId,
    pageSize: pageSize,
  );
});
