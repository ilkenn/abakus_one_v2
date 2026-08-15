import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../reservation/domain/models/reservation_area.dart';
import '../../../reservation/domain/models/reservation_summary.dart';
import '../../domain/reservations/admin_reservation_proposal_history_entry.dart';
import '../../domain/reservations/admin_reservation_summary.dart';
import 'admin_reservation_dependencies_provider.dart';

/// Live detail stream for one reservation, keyed by id.
final adminReservationDetailProvider =
    StreamProvider.family<AdminReservationSummary?, String>(
        (ref, reservationId) {
  final repository = ref.watch(adminReservationRepositoryProvider);
  return repository.watchReservationDetail(reservationId);
});

/// Live change-proposal history for one reservation, keyed by id.
final adminReservationProposalHistoryProvider =
    StreamProvider.family<List<AdminReservationProposalHistoryEntry>, String>(
        (ref, reservationId) {
  final repository = ref.watch(adminReservationRepositoryProvider);
  return repository.watchProposalHistory(reservationId);
});

/// Live preorder order detail, keyed by orderId — products, quantities,
/// modifiers, total, kitchen timing (Faz R.3A §17).
final adminPreorderOrderProvider =
    StreamProvider.family<ReservationPreorderSummary?, String>((ref, orderId) {
  final repository = ref.watch(adminReservationRepositoryProvider);
  return repository.watchPreorderOrder(orderId);
});

/// The branch's active reservation areas — used for filters and the
/// propose-change area picker. A plain `FutureProvider` (not `.family`):
/// this app targets exactly one branch, matching
/// `reservationBranchInfoProvider`'s own customer-side precedent.
final adminReservationBranchAreasProvider =
    FutureProvider<List<ReservationArea>>((ref) {
  final gateway = ref.watch(adminReservationGatewayProvider);
  return gateway.getBranchAreas(
    organizationId: adminReservationOrganizationId,
    branchId: adminReservationBranchId,
  );
});
