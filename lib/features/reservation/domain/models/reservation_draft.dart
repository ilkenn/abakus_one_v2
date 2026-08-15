import 'reservation_area.dart';

/// The one canonical state object the entire guided reservation flow reads
/// from and writes to (Faz R.2 §24 — "tek canonical state object") —
/// every step screen mutates this via `reservationDraftProvider`, never
/// its own local, step-scoped state, so navigating back/forward never
/// loses a prior selection.
class ReservationDraft {
  const ReservationDraft({
    this.partySize,
    this.area,
    this.date,
    this.time,
    this.hasPreorder = false,
    this.contactFirstName = '',
    this.contactLastName = '',
  });

  final int? partySize;
  final ReservationArea? area;

  /// The branch-local calendar date selected on the Signature Calendar —
  /// deliberately just the date; [time] carries the actual instant once a
  /// slot is chosen.
  final DateTime? date;

  /// The exact slot instant chosen in step 4 — a real, comparable `DateTime`
  /// (UTC), matching `getReservationAvailability`'s own `slot.time` shape.
  final DateTime? time;

  final bool hasPreorder;
  final String contactFirstName;
  final String contactLastName;

  bool get isReadyToReview =>
      partySize != null &&
      area != null &&
      date != null &&
      time != null &&
      contactFirstName.trim().isNotEmpty &&
      contactLastName.trim().isNotEmpty;

  ReservationDraft copyWith({
    int? partySize,
    ReservationArea? area,
    DateTime? date,
    DateTime? time,
    bool? hasPreorder,
    String? contactFirstName,
    String? contactLastName,
  }) {
    return ReservationDraft(
      partySize: partySize ?? this.partySize,
      area: area ?? this.area,
      date: date ?? this.date,
      time: time ?? this.time,
      hasPreorder: hasPreorder ?? this.hasPreorder,
      contactFirstName: contactFirstName ?? this.contactFirstName,
      contactLastName: contactLastName ?? this.contactLastName,
    );
  }

  /// [date]/[time] specifically support being reset to `null` (e.g.
  /// re-picking the date invalidates a previously-chosen time) —
  /// [copyWith]'s own `??` pattern can't express "clear this field," so
  /// these two get an explicit clearing method instead of a magic sentinel.
  ReservationDraft clearingDateAndTime() {
    return ReservationDraft(
      partySize: partySize,
      area: area,
      hasPreorder: hasPreorder,
      contactFirstName: contactFirstName,
      contactLastName: contactLastName,
    );
  }

  ReservationDraft clearingTime() {
    return ReservationDraft(
      partySize: partySize,
      area: area,
      date: date,
      hasPreorder: hasPreorder,
      contactFirstName: contactFirstName,
      contactLastName: contactLastName,
    );
  }
}
