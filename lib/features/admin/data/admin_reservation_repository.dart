import 'package:cloud_firestore/cloud_firestore.dart' as fs;

import '../../reservation/domain/models/reservation_status.dart';
import '../../reservation/domain/models/reservation_summary.dart';
import '../domain/reservations/admin_reservation_proposal_history_entry.dart';
import '../domain/reservations/admin_reservation_summary.dart';

/// Direct-Firestore reads staff are already permitted to make — both
/// `reservations/{id}` (`allow read: if canReadOrg(...)`) and
/// `reservationChangeProposals` (`allow read` for an org member of their
/// own tenant) exist as real, deployed rules already; no new callable is
/// needed for either. Mirrors `ReservationRepository`'s exact "read the
/// canonical backend-written document directly" shape.
abstract interface class AdminReservationRepository {
  /// A live stream of one reservation's full state — used by the detail
  /// panel so a confirm/reject/propose/table-assignment arriving from
  /// another admin session updates in place, no manual refresh needed.
  Stream<AdminReservationSummary?> watchReservationDetail(String reservationId);

  /// The full change-proposal history for one reservation, newest first —
  /// `reservationChangeProposals` is genuinely staff-readable (unlike the
  /// customer-facing flow, which only ever sees the current proposal
  /// denormalized onto the Reservation itself).
  Stream<List<AdminReservationProposalHistoryEntry>> watchProposalHistory(
      String reservationId);

  /// The linked preorder order's full detail — products, quantities,
  /// modifiers, total, kitchen timing (Faz R.3A §17). Reuses
  /// `ReservationPreorderSummary`/`ReservationPreorderLineSummary`
  /// (`features/reservation/domain`) and the exact same `orders/{id}`
  /// mapping `FirestoreReservationRepository._mapPreorder` already
  /// establishes — `orders` is already staff-readable via
  /// `isOrgMember(resource.data.organizationId)`, no new rule needed.
  Stream<ReservationPreorderSummary?> watchPreorderOrder(String orderId);
}

class FirestoreAdminReservationRepository
    implements AdminReservationRepository {
  FirestoreAdminReservationRepository({fs.FirebaseFirestore? firestore})
      : _firestore = firestore ?? fs.FirebaseFirestore.instance;

  final fs.FirebaseFirestore _firestore;

  @override
  Stream<AdminReservationSummary?> watchReservationDetail(
      String reservationId) {
    return _firestore
        .collection('reservations')
        .doc(reservationId)
        .snapshots()
        .map((doc) {
      if (!doc.exists) return null;
      final data = doc.data()!;
      return AdminReservationSummary(
        id: doc.id,
        status: ReservationStatus.fromName(data['status'] as String),
        partySize: data['partySize'] as int,
        requestedTime: (data['requestedTime'] as fs.Timestamp).toDate(),
        requestedAreaId: data['requestedAreaId'] as String,
        contactFirstName: data['contactFirstName'] as String? ?? '',
        contactLastName: data['contactLastName'] as String? ?? '',
        confirmedTime: (data['confirmedTime'] as fs.Timestamp?)?.toDate(),
        confirmedAreaId: data['confirmedAreaId'] as String?,
        assignedTableId: data['assignedTableId'] as String?,
        preorderOrderId: data['preorderOrderId'] as String?,
        activeProposalCustomerResponseDeadlineAt:
            (data['activeProposalCustomerResponseDeadlineAt'] as fs.Timestamp?)
                ?.toDate(),
      );
    });
  }

  @override
  Stream<List<AdminReservationProposalHistoryEntry>> watchProposalHistory(
      String reservationId) {
    return _firestore
        .collection('reservationChangeProposals')
        .where('reservationId', isEqualTo: reservationId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) =>
            [for (final doc in snapshot.docs) _mapProposal(doc.data())]);
  }

  @override
  Stream<ReservationPreorderSummary?> watchPreorderOrder(String orderId) {
    return _firestore.collection('orders').doc(orderId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return _mapPreorder(doc.id, doc.data()!);
    });
  }

  ReservationPreorderSummary _mapPreorder(
      String orderId, Map<String, dynamic> data) {
    final linesJson = List<Map<String, dynamic>>.from(
      (data['lines'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
    );
    final lines = [for (final line in linesJson) _mapPreorderLine(line)];
    final pricing = Map<String, dynamic>.from(data['pricing'] as Map);
    final grandTotal = Map<String, dynamic>.from(pricing['grandTotal'] as Map);
    final kitchenReleaseAtTimestamp =
        data['kitchenReleaseAtTimestamp'] as fs.Timestamp?;

    return ReservationPreorderSummary(
      orderId: orderId,
      status: ReservationPreorderStatus.fromName(data['status'] as String),
      kitchenReleaseAt: kitchenReleaseAtTimestamp?.toDate(),
      lines: lines,
      grandTotalMinorUnits: grandTotal['minorUnits'] as int,
    );
  }

  ReservationPreorderLineSummary _mapPreorderLine(Map<String, dynamic> line) {
    final unitPrice = Map<String, dynamic>.from(line['unitPrice'] as Map);
    final unitPriceMinorUnits = unitPrice['minorUnits'] as int;
    final modifiersJson = List<Map<String, dynamic>>.from(
      (line['modifiers'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map)),
    );
    var modifierTotalMinorUnits = 0;
    final modifierNames = <String>[];
    for (final modifier in modifiersJson) {
      final unitExtraPrice =
          Map<String, dynamic>.from(modifier['unitExtraPrice'] as Map);
      final quantity = modifier['quantity'] as int;
      modifierTotalMinorUnits +=
          (unitExtraPrice['minorUnits'] as int) * quantity;
      modifierNames.add(modifier['optionName'] as String);
    }
    final quantity = line['quantity'] as int;
    final lineDiscount = Map<String, dynamic>.from(line['lineDiscount'] as Map);
    final lineTotalMinorUnits =
        (unitPriceMinorUnits + modifierTotalMinorUnits) * quantity -
            (lineDiscount['minorUnits'] as int);

    return ReservationPreorderLineSummary(
      productName: line['productName'] as String,
      quantity: quantity,
      modifierNames: modifierNames,
      lineTotalMinorUnits: lineTotalMinorUnits,
    );
  }

  AdminReservationProposalHistoryEntry _mapProposal(Map<String, dynamic> data) {
    return AdminReservationProposalHistoryEntry(
      proposalId: data['proposalId'] as String,
      status: AdminProposalStatus.fromName(data['status'] as String),
      fromTime: (data['fromTime'] as fs.Timestamp).toDate(),
      fromAreaId: data['fromAreaId'] as String,
      proposedTime: (data['proposedTime'] as fs.Timestamp).toDate(),
      proposedAreaId: data['proposedAreaId'] as String,
      createdByStaffId: data['createdByStaffId'] as String,
      createdAt: (data['createdAt'] as fs.Timestamp).toDate(),
      customerResponseDeadlineAt:
          (data['customerResponseDeadlineAt'] as fs.Timestamp).toDate(),
      respondedAt: (data['respondedAt'] as fs.Timestamp?)?.toDate(),
    );
  }
}
