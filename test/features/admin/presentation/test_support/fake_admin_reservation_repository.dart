import 'dart:async';

import 'package:abakus_one_v2/features/admin/data/admin_reservation_repository.dart';
import 'package:abakus_one_v2/features/admin/domain/reservations/admin_reservation_proposal_history_entry.dart';
import 'package:abakus_one_v2/features/admin/domain/reservations/admin_reservation_summary.dart';
import 'package:abakus_one_v2/features/reservation/domain/models/reservation_summary.dart';

/// A fully in-memory, stream-controller-backed [AdminReservationRepository]
/// fake — no real Firestore SDK involved. Each reservation/history stream
/// is independently controllable via [emitDetail]/[emitHistory].
class FakeAdminReservationRepository implements AdminReservationRepository {
  final Map<String, StreamController<AdminReservationSummary?>>
      _detailControllers = {};
  final Map<String,
          StreamController<List<AdminReservationProposalHistoryEntry>>>
      _historyControllers = {};
  final Map<String, StreamController<ReservationPreorderSummary?>>
      _preorderControllers = {};

  StreamController<AdminReservationSummary?> _detailController(String id) =>
      _detailControllers.putIfAbsent(
          id, () => StreamController<AdminReservationSummary?>.broadcast());
  StreamController<List<AdminReservationProposalHistoryEntry>>
      _historyController(String id) => _historyControllers.putIfAbsent(
          id,
          () => StreamController<
              List<AdminReservationProposalHistoryEntry>>.broadcast());
  StreamController<ReservationPreorderSummary?> _preorderController(
          String id) =>
      _preorderControllers.putIfAbsent(
          id, () => StreamController<ReservationPreorderSummary?>.broadcast());

  void emitDetail(String reservationId, AdminReservationSummary? summary) {
    _detailController(reservationId).add(summary);
  }

  void emitHistory(String reservationId,
      List<AdminReservationProposalHistoryEntry> entries) {
    _historyController(reservationId).add(entries);
  }

  void emitPreorder(String orderId, ReservationPreorderSummary? summary) {
    _preorderController(orderId).add(summary);
  }

  void dispose() {
    for (final controller in _detailControllers.values) {
      controller.close();
    }
    for (final controller in _historyControllers.values) {
      controller.close();
    }
    for (final controller in _preorderControllers.values) {
      controller.close();
    }
  }

  @override
  Stream<AdminReservationSummary?> watchReservationDetail(
          String reservationId) =>
      _detailController(reservationId).stream;

  @override
  Stream<List<AdminReservationProposalHistoryEntry>> watchProposalHistory(
          String reservationId) =>
      _historyController(reservationId).stream;

  @override
  Stream<ReservationPreorderSummary?> watchPreorderOrder(String orderId) =>
      _preorderController(orderId).stream;
}
