import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../reservation/domain/models/reservation_status.dart';
import '../../data/admin_reservation_gateway.dart';
import 'admin_reservation_dependencies_provider.dart';

/// One page's worth of query parameters — equality-based, so
/// `FutureProvider.family` re-fetches exactly when a filter genuinely
/// changes, never on every rebuild.
class AdminReservationListQuery {
  const AdminReservationListQuery({
    required this.dateFrom,
    required this.dateTo,
    this.statuses,
    this.areaId,
    this.cursor,
    this.pageSize = 50,
  });

  final DateTime dateFrom;
  final DateTime dateTo;
  final List<ReservationStatus>? statuses;
  final String? areaId;
  final String? cursor;
  final int pageSize;

  @override
  bool operator ==(Object other) {
    return other is AdminReservationListQuery &&
        other.dateFrom == dateFrom &&
        other.dateTo == dateTo &&
        _listEquals(other.statuses, statuses) &&
        other.areaId == areaId &&
        other.cursor == cursor &&
        other.pageSize == pageSize;
  }

  @override
  int get hashCode => Object.hash(
        dateFrom,
        dateTo,
        statuses == null ? null : Object.hashAll(statuses!),
        areaId,
        cursor,
        pageSize,
      );
}

bool _listEquals<T>(List<T>? a, List<T>? b) {
  if (a == null) return b == null;
  if (b == null || a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Faz R.3A — the admin list/calendar's server-authoritative data source.
/// Re-fetches whenever [AdminReservationListQuery] changes (the record's
/// own equality naturally invalidates/re-runs the request, mirroring
/// `reservationAvailabilityProvider`'s exact shape from the customer-side
/// flow).
final adminReservationListProvider =
    FutureProvider.family<AdminReservationListPage, AdminReservationListQuery>(
        (ref, query) {
  final gateway = ref.watch(adminReservationGatewayProvider);
  return gateway.listReservationsForBranch(
    organizationId: adminReservationOrganizationId,
    branchId: adminReservationBranchId,
    dateFrom: query.dateFrom,
    dateTo: query.dateTo,
    statuses: query.statuses,
    areaId: query.areaId,
    cursor: query.cursor,
    pageSize: query.pageSize,
  );
});
