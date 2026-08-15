import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/reservation_area.dart';
import '../../domain/models/reservation_draft.dart';

/// The single canonical draft state (Faz R.2 §24) every step screen reads
/// from and writes to — never step-local `State`, so navigating back/forth
/// through the guided flow never loses a prior selection.
class ReservationDraftNotifier extends Notifier<ReservationDraft> {
  @override
  ReservationDraft build() => const ReservationDraft();

  void setPartySize(int partySize) {
    state = state.copyWith(partySize: partySize);
  }

  void setArea(ReservationArea area) {
    state = state.copyWith(area: area);
  }

  /// Picking a new date invalidates any previously-chosen time — the
  /// available slots for a different day are a different, re-fetched set.
  void setDate(DateTime date) {
    state = state.clearingTime().copyWith(date: date);
  }

  void setTime(DateTime time) {
    state = state.copyWith(time: time);
  }

  void setHasPreorder(bool hasPreorder) {
    state = state.copyWith(hasPreorder: hasPreorder);
  }

  void setContactName({required String firstName, required String lastName}) {
    state = state.copyWith(
      contactFirstName: firstName,
      contactLastName: lastName,
    );
  }

  void reset() {
    state = const ReservationDraft();
  }
}

final reservationDraftProvider =
    NotifierProvider<ReservationDraftNotifier, ReservationDraft>(
  ReservationDraftNotifier.new,
);
