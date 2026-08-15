import 'package:cloud_functions/cloud_functions.dart' as functions;

import '../../reservation/domain/models/reservation_area.dart';
import '../../reservation/domain/models/reservation_status.dart';
import '../domain/reservations/admin_reservation_summary.dart';

/// Mirrors `ReservationException`'s exact shape (`features/reservation/
/// data/reservation_gateway.dart`) — deliberately duplicated rather than
/// imported: this is a staff-facing error, its Turkish mapping
/// (`admin_reservation_error_messages.dart`) is entirely separate
/// operational copy from the customer-facing one, and the two features'
/// data layers otherwise never cross-import.
class AdminReservationException implements Exception {
  final String code;
  final String message;
  final Map<String, dynamic>? details;

  const AdminReservationException(this.code, this.message, [this.details]);

  @override
  String toString() => 'AdminReservationException($code): $message';
}

class AdminReservationListPage {
  const AdminReservationListPage(
      {required this.reservations, required this.nextCursor});

  final List<AdminReservationSummary> reservations;
  final String? nextCursor;
}

class ReservationTableOption {
  const ReservationTableOption({
    required this.id,
    required this.displayName,
    required this.capacity,
    required this.available,
    required this.isCurrentlyAssigned,
  });

  final String id;
  final String displayName;
  final int? capacity;
  final bool available;
  final bool isCurrentlyAssigned;
}

class AssignTableResult {
  const AssignTableResult({required this.assigned, required this.reassigned});
  final bool assigned;
  final bool reassigned;
}

class OpenTableResult {
  const OpenTableResult({required this.opened});
  final bool opened;
}

/// Thrown specifically for `openReservationTable`'s soft "active walk-in
/// session" conflict (`{code: "activeSessionExists", ...}` in the
/// backend's `HttpsError` details) — distinguished from every other
/// `failed-precondition` so the UI can offer the acknowledge-and-retry
/// handshake only for this exact case, never for a genuinely
/// unrecoverable precondition failure.
class ActiveSessionConflictException implements Exception {
  const ActiveSessionConflictException(this.conflictingSessionCount);
  final int conflictingSessionCount;
}

class BranchOperatingHoursInterval {
  const BranchOperatingHoursInterval({required this.start, required this.end});
  final String start; // "HH:mm"
  final String end;

  Map<String, dynamic> toJson() => {'start': start, 'end': end};
}

class BranchOperatingHoursDateOverride {
  const BranchOperatingHoursDateOverride(
      {required this.closed, this.intervals = const []});
  final bool closed;
  final List<BranchOperatingHoursInterval> intervals;

  Map<String, dynamic> toJson() => {
        'closed': closed,
        if (!closed) 'intervals': [for (final i in intervals) i.toJson()],
      };
}

class BranchOperatingHoursSnapshot {
  const BranchOperatingHoursSnapshot({
    required this.exists,
    required this.weeklySchedule,
    required this.dateOverrides,
  });

  final bool exists;

  /// Keyed by lowercase English weekday name (`monday`..`sunday`), matching
  /// the backend's own field names exactly.
  final Map<String, List<BranchOperatingHoursInterval>> weeklySchedule;
  final Map<String, BranchOperatingHoursDateOverride> dateOverrides;
}

/// The admin-facing boundary onto the server-authoritative reservation
/// backend's staff-only surface — `respondToReservation`,
/// `assignReservationTable`, `openReservationTable`/`closeReservationTable`,
/// `listReservationsForBranch`, `getBranchOperatingHours`/
/// `updateBranchOperatingHours`. Mirrors `ReservationGateway`'s exact
/// shape (narrow, mockable interface + real implementation).
abstract interface class AdminReservationGateway {
  Future<AdminReservationListPage> listReservationsForBranch({
    required String organizationId,
    required String branchId,
    required DateTime dateFrom,
    required DateTime dateTo,
    List<ReservationStatus>? statuses,
    String? areaId,
    String? cursor,
    int pageSize = 50,
  });

  Future<void> confirmReservation({required String reservationId});

  Future<void> rejectReservation({
    required String reservationId,
    required String reasonCode,
    String? reason,
  });

  Future<void> proposeChange({
    required String reservationId,
    required DateTime proposedTime,
    required String proposedAreaId,
  });

  /// Faz R.3B — staff cancellation. Server-side authority resolves the
  /// caller as staff (never a client-supplied actorType); unlike a
  /// customer's own cancellation, staff is never bound by the customer
  /// cancellation cutoff, but a preorder already released to the kitchen
  /// is still never auto-cancelled (admin UI must warn before calling this
  /// in that case).
  Future<void> cancelReservation({
    required String reservationId,
    String? reasonCode,
  });

  /// Faz R.3B — staff-only. Only a `confirmed` reservation whose
  /// `confirmedTime` has already passed may be completed; never cancels a
  /// linked preorder.
  Future<void> completeReservation({required String reservationId});

  /// Faz R.3B — staff-only. Only a `confirmed` reservation whose
  /// `confirmedTime` has already passed may be marked no-show; a
  /// still-`pendingConfirmation` preorder is auto-cancelled, a released one
  /// is preserved.
  Future<void> markReservationNoShow({required String reservationId});

  Future<AssignTableResult> assignTable({
    required String reservationId,
    required String tableId,
  });

  /// Throws [ActiveSessionConflictException] on the soft conflict — the
  /// caller retries with [acknowledgeActiveSessionConflict] = true.
  Future<OpenTableResult> openTable({
    required String reservationId,
    bool acknowledgeActiveSessionConflict = false,
  });

  Future<void> closeTable({required String reservationId});

  /// Every active table in [reservationId]'s confirmed area, each
  /// annotated with real availability for that reservation's exact time
  /// window — only meaningful once the reservation is confirmed.
  Future<List<ReservationTableOption>> listTablesForArea(
      {required String reservationId});

  Future<List<ReservationArea>> getBranchAreas({
    required String organizationId,
    required String branchId,
  });

  Future<BranchOperatingHoursSnapshot> getBranchOperatingHours({
    required String organizationId,
    required String branchId,
  });

  Future<void> updateBranchOperatingHours({
    required String organizationId,
    required String branchId,
    required Map<String, List<BranchOperatingHoursInterval>> weeklySchedule,
    Map<String, BranchOperatingHoursDateOverride> dateOverrides = const {},
  });
}

class FirebaseAdminReservationGateway implements AdminReservationGateway {
  const FirebaseAdminReservationGateway();

  Never _rethrow(functions.FirebaseFunctionsException error) {
    throw AdminReservationException(
      error.code,
      error.message ?? 'İşlem tamamlanamadı.',
      error.details is Map
          ? Map<String, dynamic>.from(error.details as Map)
          : null,
    );
  }

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
    final callable = functions.FirebaseFunctions.instance
        .httpsCallable('listReservationsForBranch');
    try {
      final result = await callable.call<Map<String, dynamic>>({
        'organizationId': organizationId,
        'branchId': branchId,
        'dateFrom': dateFrom.toIso8601String(),
        'dateTo': dateTo.toIso8601String(),
        if (statuses != null) 'statuses': [for (final s in statuses) s.name],
        if (areaId != null) 'areaId': areaId,
        if (cursor != null) 'cursor': cursor,
        'pageSize': pageSize,
      });
      final data = result.data;
      final rawList = List<Map<String, dynamic>>.from(
        (data['reservations'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map)),
      );
      return AdminReservationListPage(
        reservations: [for (final r in rawList) _mapSummary(r)],
        nextCursor: data['nextCursor'] as String?,
      );
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  AdminReservationSummary _mapSummary(Map<String, dynamic> r) {
    return AdminReservationSummary(
      id: r['id'] as String,
      status: ReservationStatus.fromName(r['status'] as String),
      partySize: r['partySize'] as int,
      requestedTime: DateTime.parse(r['requestedTime'] as String),
      requestedAreaId: r['requestedAreaId'] as String,
      contactFirstName: r['contactFirstName'] as String,
      contactLastName: r['contactLastName'] as String,
      confirmedTime: r['confirmedTime'] != null
          ? DateTime.parse(r['confirmedTime'] as String)
          : null,
      confirmedAreaId: r['confirmedAreaId'] as String?,
      assignedTableId: r['assignedTableId'] as String?,
      preorderOrderId: r['preorderOrderId'] as String?,
      activeProposalCustomerResponseDeadlineAt:
          r['activeProposalCustomerResponseDeadlineAt'] != null
              ? DateTime.parse(
                  r['activeProposalCustomerResponseDeadlineAt'] as String)
              : null,
    );
  }

  @override
  Future<void> confirmReservation({required String reservationId}) async {
    final callable = functions.FirebaseFunctions.instance
        .httpsCallable('respondToReservation');
    try {
      await callable.call<Map<String, dynamic>>(
          {'reservationId': reservationId, 'action': 'confirm'});
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<void> rejectReservation({
    required String reservationId,
    required String reasonCode,
    String? reason,
  }) async {
    final callable = functions.FirebaseFunctions.instance
        .httpsCallable('respondToReservation');
    try {
      await callable.call<Map<String, dynamic>>({
        'reservationId': reservationId,
        'action': 'reject',
        'reasonCode': reasonCode,
        if (reason != null) 'reason': reason,
      });
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<void> cancelReservation({
    required String reservationId,
    String? reasonCode,
  }) async {
    final callable =
        functions.FirebaseFunctions.instance.httpsCallable('cancelReservation');
    try {
      await callable.call<Map<String, dynamic>>({
        'reservationId': reservationId,
        if (reasonCode != null) 'reasonCode': reasonCode,
      });
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<void> completeReservation({required String reservationId}) async {
    final callable = functions.FirebaseFunctions.instance
        .httpsCallable('completeReservation');
    try {
      await callable
          .call<Map<String, dynamic>>({'reservationId': reservationId});
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<void> markReservationNoShow({required String reservationId}) async {
    final callable = functions.FirebaseFunctions.instance
        .httpsCallable('markReservationNoShow');
    try {
      await callable
          .call<Map<String, dynamic>>({'reservationId': reservationId});
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<void> proposeChange({
    required String reservationId,
    required DateTime proposedTime,
    required String proposedAreaId,
  }) async {
    final callable = functions.FirebaseFunctions.instance
        .httpsCallable('respondToReservation');
    try {
      await callable.call<Map<String, dynamic>>({
        'reservationId': reservationId,
        'action': 'proposeChange',
        'proposedTime': proposedTime.toIso8601String(),
        'proposedAreaId': proposedAreaId,
      });
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<AssignTableResult> assignTable({
    required String reservationId,
    required String tableId,
  }) async {
    final callable = functions.FirebaseFunctions.instance
        .httpsCallable('assignReservationTable');
    try {
      final result = await callable.call<Map<String, dynamic>>({
        'reservationId': reservationId,
        'tableId': tableId,
      });
      return AssignTableResult(
        assigned: result.data['assigned'] as bool,
        reassigned: result.data['reassigned'] as bool? ?? false,
      );
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<OpenTableResult> openTable({
    required String reservationId,
    bool acknowledgeActiveSessionConflict = false,
  }) async {
    final callable = functions.FirebaseFunctions.instance
        .httpsCallable('openReservationTable');
    try {
      final result = await callable.call<Map<String, dynamic>>({
        'reservationId': reservationId,
        'acknowledgeActiveSessionConflict': acknowledgeActiveSessionConflict,
      });
      return OpenTableResult(opened: result.data['opened'] as bool);
    } on functions.FirebaseFunctionsException catch (error) {
      final details = error.details;
      if (error.code == 'failed-precondition' &&
          details is Map &&
          details['code'] == 'activeSessionExists') {
        throw ActiveSessionConflictException(
            details['conflictingSessionCount'] as int? ?? 0);
      }
      _rethrow(error);
    }
  }

  @override
  Future<void> closeTable({required String reservationId}) async {
    final callable = functions.FirebaseFunctions.instance
        .httpsCallable('closeReservationTable');
    try {
      await callable
          .call<Map<String, dynamic>>({'reservationId': reservationId});
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<List<ReservationTableOption>> listTablesForArea(
      {required String reservationId}) async {
    final callable = functions.FirebaseFunctions.instance
        .httpsCallable('listReservationTablesForArea');
    try {
      final result = await callable
          .call<Map<String, dynamic>>({'reservationId': reservationId});
      final raw = List<Map<String, dynamic>>.from(
        (result.data['tables'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map)),
      );
      return [
        for (final t in raw)
          ReservationTableOption(
            id: t['id'] as String,
            displayName: t['displayName'] as String,
            capacity: t['capacity'] as int?,
            available: t['available'] as bool,
            isCurrentlyAssigned: t['isCurrentlyAssigned'] as bool,
          ),
      ];
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<List<ReservationArea>> getBranchAreas({
    required String organizationId,
    required String branchId,
  }) async {
    final callable = functions.FirebaseFunctions.instance
        .httpsCallable('getReservationBranchInfoForStaff');
    try {
      final result = await callable.call<Map<String, dynamic>>({
        'organizationId': organizationId,
        'branchId': branchId,
      });
      final raw = List<Map<String, dynamic>>.from(
        (result.data['areas'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map)),
      );
      return [
        for (final a in raw)
          ReservationArea(
              id: a['id'] as String, displayName: a['displayName'] as String),
      ];
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<BranchOperatingHoursSnapshot> getBranchOperatingHours({
    required String organizationId,
    required String branchId,
  }) async {
    final callable = functions.FirebaseFunctions.instance
        .httpsCallable('getBranchOperatingHours');
    try {
      final result = await callable.call<Map<String, dynamic>>({
        'organizationId': organizationId,
        'branchId': branchId,
      });
      final data = result.data;
      final exists = data['exists'] as bool;
      if (!exists) {
        return const BranchOperatingHoursSnapshot(
            exists: false, weeklySchedule: {}, dateOverrides: {});
      }
      final weeklyRaw =
          Map<String, dynamic>.from(data['weeklySchedule'] as Map);
      final weeklySchedule = <String, List<BranchOperatingHoursInterval>>{
        for (final entry in weeklyRaw.entries)
          entry.key: [
            for (final i in (entry.value as List))
              BranchOperatingHoursInterval(
                start: (i as Map)['start'] as String,
                end: i['end'] as String,
              ),
          ],
      };
      final overridesRaw =
          Map<String, dynamic>.from(data['dateOverrides'] as Map);
      final dateOverrides = <String, BranchOperatingHoursDateOverride>{
        for (final entry in overridesRaw.entries)
          entry.key: BranchOperatingHoursDateOverride(
            closed: (entry.value as Map)['closed'] as bool,
            intervals: [
              for (final i
                  in ((entry.value as Map)['intervals'] as List? ?? []))
                BranchOperatingHoursInterval(
                    start: (i as Map)['start'] as String,
                    end: i['end'] as String),
            ],
          ),
      };
      return BranchOperatingHoursSnapshot(
        exists: true,
        weeklySchedule: weeklySchedule,
        dateOverrides: dateOverrides,
      );
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }

  @override
  Future<void> updateBranchOperatingHours({
    required String organizationId,
    required String branchId,
    required Map<String, List<BranchOperatingHoursInterval>> weeklySchedule,
    Map<String, BranchOperatingHoursDateOverride> dateOverrides = const {},
  }) async {
    final callable = functions.FirebaseFunctions.instance
        .httpsCallable('updateBranchOperatingHours');
    try {
      await callable.call<Map<String, dynamic>>({
        'organizationId': organizationId,
        'branchId': branchId,
        'weeklySchedule': {
          for (final entry in weeklySchedule.entries)
            entry.key: [for (final i in entry.value) i.toJson()],
        },
        'dateOverrides': {
          for (final entry in dateOverrides.entries)
            entry.key: entry.value.toJson(),
        },
      });
    } on functions.FirebaseFunctionsException catch (error) {
      _rethrow(error);
    }
  }
}
