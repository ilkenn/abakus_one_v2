import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../navigation/presentation/providers/current_branch_provider.dart';
import '../../../orders/domain/models/order.dart';
import '../../../orders/presentation/providers/orders_provider.dart';
import 'admin_dependencies_provider.dart';

/// Admin Siparişler — every order for the current org/branch, regardless
/// of status or channel. Mirrors `admin_financial_list_providers.dart`'s
/// exact shape: `organizationId`/`branchId` resolved from
/// [currentOrganizationIdProvider]/[currentBranchIdProvider] inside the
/// provider body (never baked into the family argument), so switching
/// branch/org context automatically invalidates this via its own
/// `ref.watch`. A live stream (not a one-shot fetch), matching
/// `KitchenDisplayBoardScreen`'s own "no manual reload needed" precedent —
/// unlike the financial list providers, which are intentionally one-shot
/// per `adminFinancialView.ts`'s own doc comment (a bounded, permission-
/// gated callable, not a live stream); Orders reads directly off
/// `CanonicalOrderRepository`, which already exposes a live view.
final adminOrdersProvider = StreamProvider<List<Order>>((ref) {
  final repository = ref.watch(canonicalOrderRepositoryProvider);
  final organizationId = ref.watch(currentOrganizationIdProvider);
  final branchId = ref.watch(currentBranchIdProvider);
  return repository.watchByBranch(
    organizationId: organizationId,
    branchId: branchId,
  );
});
