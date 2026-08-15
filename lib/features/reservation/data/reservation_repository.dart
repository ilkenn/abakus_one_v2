import 'package:cloud_firestore/cloud_firestore.dart' as fs;

import '../domain/models/reservation_status.dart';
import '../domain/models/reservation_summary.dart';

/// Reads the customer's own reservation (plus its linked preorder order,
/// if any) directly from Firestore — both `reservations/{id}` and
/// `orders/{preorderOrderId}` are already owner-readable in
/// `firestore.rules` (`customerId == request.auth.uid`), so no callable is
/// needed for this read path, matching `FirestoreCanonicalOrderRepository`'s
/// own "read the canonical backend-written document directly" precedent.
/// Write access is never attempted here — `submitReservation`/
/// `respondToProposedChange` remain the only ways this data ever changes.
abstract interface class ReservationRepository {
  /// A live stream of the customer's reservation (and its preorder, if
  /// linked) — used by the detail screen so a restaurant confirm/propose/
  /// reject arriving while the screen is open updates in place, no manual
  /// refresh needed.
  Stream<ReservationSummary?> watchReservation(String reservationId);
}

class FirestoreReservationRepository implements ReservationRepository {
  FirestoreReservationRepository({fs.FirebaseFirestore? firestore})
      : _firestore = firestore ?? fs.FirebaseFirestore.instance;

  final fs.FirebaseFirestore _firestore;

  @override
  Stream<ReservationSummary?> watchReservation(String reservationId) {
    return _firestore
        .collection('reservations')
        .doc(reservationId)
        .snapshots()
        .asyncMap((doc) async {
      if (!doc.exists) return null;
      final data = doc.data()!;

      ReservationPreorderSummary? preorder;
      final preorderOrderId = data['preorderOrderId'] as String?;
      if (preorderOrderId != null) {
        final orderDoc =
            await _firestore.collection('orders').doc(preorderOrderId).get();
        if (orderDoc.exists) {
          preorder = _mapPreorder(orderDoc.id, orderDoc.data()!);
        }
      }

      return _mapReservation(doc.id, data, preorder);
    });
  }

  ReservationSummary _mapReservation(
    String id,
    Map<String, dynamic> data,
    ReservationPreorderSummary? preorder,
  ) {
    ReservationProposalSnapshot? activeProposal;
    final proposedTime = data['activeProposalProposedTime'] as fs.Timestamp?;
    final proposedAreaId = data['activeProposalProposedAreaId'] as String?;
    final proposalDeadline =
        data['activeProposalCustomerResponseDeadlineAt'] as fs.Timestamp?;
    if (proposedTime != null &&
        proposedAreaId != null &&
        proposalDeadline != null) {
      activeProposal = ReservationProposalSnapshot(
        proposedTime: proposedTime.toDate(),
        proposedAreaId: proposedAreaId,
        customerResponseDeadlineAt: proposalDeadline.toDate(),
      );
    }

    final confirmedTime = data['confirmedTime'] as fs.Timestamp?;

    return ReservationSummary(
      id: id,
      status: ReservationStatus.fromName(data['status'] as String),
      partySize: data['partySize'] as int,
      requestedTime: (data['requestedTime'] as fs.Timestamp).toDate(),
      requestedAreaId: data['requestedAreaId'] as String,
      confirmedTime: confirmedTime?.toDate(),
      confirmedAreaId: data['confirmedAreaId'] as String?,
      activeProposalId: data['activeProposalId'] as String?,
      activeProposal: activeProposal,
      preorder: preorder,
    );
  }

  ReservationPreorderSummary _mapPreorder(
      String orderId, Map<String, dynamic> data) {
    final linesJson = List<Map<String, dynamic>>.from(
      (data['lines'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
    );
    final lines = [
      for (final line in linesJson) _mapPreorderLine(line),
    ];
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
}
