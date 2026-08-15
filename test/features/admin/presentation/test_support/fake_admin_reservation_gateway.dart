import 'package:abakus_one_v2/features/admin/data/admin_reservation_gateway.dart';
import 'package:abakus_one_v2/features/reservation/domain/models/reservation_area.dart';
import 'package:abakus_one_v2/features/reservation/domain/models/reservation_status.dart';

/// A fully in-memory, call-recording [AdminReservationGateway] fake — no
/// real `cloud_functions` SDK involved (unavailable under `flutter test`).
/// Every test configures only the fields it needs; everything else
/// defaults to an empty/successful no-op.
class FakeAdminReservationGateway implements AdminReservationGateway {
  AdminReservationListPage listPageToReturn =
      const AdminReservationListPage(reservations: [], nextCursor: null);
  Object? listError;
  int listCallCount = 0;

  final List<String> confirmCalls = [];
  Object? confirmError;

  final List<({String reservationId, String reasonCode, String? reason})>
      rejectCalls = [];
  Object? rejectError;

  final List<
      ({
        String reservationId,
        DateTime proposedTime,
        String proposedAreaId
      })> proposeChangeCalls = [];
  Object? proposeChangeError;

  final List<({String reservationId, String? reasonCode})> cancelCalls = [];
  Object? cancelError;

  final List<String> completeCalls = [];
  Object? completeError;

  final List<String> noShowCalls = [];
  Object? noShowError;

  final List<({String reservationId, String tableId})> assignTableCalls = [];
  AssignTableResult assignTableResultToReturn =
      const AssignTableResult(assigned: true, reassigned: false);
  Object? assignTableError;

  final List<({String reservationId, bool acknowledge})> openTableCalls = [];
  OpenTableResult openTableResultToReturn = const OpenTableResult(opened: true);
  Object? openTableError;

  final List<String> closeTableCalls = [];
  Object? closeTableError;

  List<ReservationTableOption> tablesToReturn = const [];
  Object? tablesError;

  List<ReservationArea> areasToReturn = const [];

  BranchOperatingHoursSnapshot hoursToReturn =
      const BranchOperatingHoursSnapshot(
          exists: false, weeklySchedule: {}, dateOverrides: {});
  Object? getHoursError;

  final List<Map<String, dynamic>> updateHoursCalls = [];
  Object? updateHoursError;

  @override
  Future<AdminReservationListPage> listReservationsForBranch({
    required String organizationId,
    required String branchId,
    required DateTime dateFrom,
    required DateTime dateTo,
    List<ReservationStatus>? statuses,
    String? areaId,
    String? cursor,
    int pageSize = 50,
  }) async {
    listCallCount++;
    if (listError != null) throw listError!;
    return listPageToReturn;
  }

  @override
  Future<void> confirmReservation({required String reservationId}) async {
    confirmCalls.add(reservationId);
    if (confirmError != null) throw confirmError!;
  }

  @override
  Future<void> rejectReservation({
    required String reservationId,
    required String reasonCode,
    String? reason,
  }) async {
    rejectCalls.add(
        (reservationId: reservationId, reasonCode: reasonCode, reason: reason));
    if (rejectError != null) throw rejectError!;
  }

  @override
  Future<void> proposeChange({
    required String reservationId,
    required DateTime proposedTime,
    required String proposedAreaId,
  }) async {
    proposeChangeCalls.add((
      reservationId: reservationId,
      proposedTime: proposedTime,
      proposedAreaId: proposedAreaId
    ));
    if (proposeChangeError != null) throw proposeChangeError!;
  }

  @override
  Future<void> cancelReservation({
    required String reservationId,
    String? reasonCode,
  }) async {
    cancelCalls.add((reservationId: reservationId, reasonCode: reasonCode));
    if (cancelError != null) throw cancelError!;
  }

  @override
  Future<void> completeReservation({required String reservationId}) async {
    completeCalls.add(reservationId);
    if (completeError != null) throw completeError!;
  }

  @override
  Future<void> markReservationNoShow({required String reservationId}) async {
    noShowCalls.add(reservationId);
    if (noShowError != null) throw noShowError!;
  }

  @override
  Future<AssignTableResult> assignTable(
      {required String reservationId, required String tableId}) async {
    assignTableCalls.add((reservationId: reservationId, tableId: tableId));
    if (assignTableError != null) throw assignTableError!;
    return assignTableResultToReturn;
  }

  @override
  Future<OpenTableResult> openTable({
    required String reservationId,
    bool acknowledgeActiveSessionConflict = false,
  }) async {
    openTableCalls.add((
      reservationId: reservationId,
      acknowledge: acknowledgeActiveSessionConflict
    ));
    if (openTableError != null) throw openTableError!;
    return openTableResultToReturn;
  }

  @override
  Future<void> closeTable({required String reservationId}) async {
    closeTableCalls.add(reservationId);
    if (closeTableError != null) throw closeTableError!;
  }

  @override
  Future<List<ReservationTableOption>> listTablesForArea(
      {required String reservationId}) async {
    if (tablesError != null) throw tablesError!;
    return tablesToReturn;
  }

  @override
  Future<List<ReservationArea>> getBranchAreas(
      {required String organizationId, required String branchId}) async {
    return areasToReturn;
  }

  @override
  Future<BranchOperatingHoursSnapshot> getBranchOperatingHours({
    required String organizationId,
    required String branchId,
  }) async {
    if (getHoursError != null) throw getHoursError!;
    return hoursToReturn;
  }

  @override
  Future<void> updateBranchOperatingHours({
    required String organizationId,
    required String branchId,
    required Map<String, List<BranchOperatingHoursInterval>> weeklySchedule,
    Map<String, BranchOperatingHoursDateOverride> dateOverrides = const {},
  }) async {
    updateHoursCalls.add({
      'organizationId': organizationId,
      'branchId': branchId,
      'weeklySchedule': weeklySchedule,
      'dateOverrides': dateOverrides,
    });
    if (updateHoursError != null) throw updateHoursError!;
  }
}
