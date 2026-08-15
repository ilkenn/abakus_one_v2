/// One candidate time slot from `getReservationAvailability` — advisory
/// only. `available == false` never blocks submission (Faz R.0's own
/// product rule: a full slot can still be requested) — the UI uses this
/// only to shape the soft-decline copy, never to disable the slot.
class ReservationAvailabilitySlot {
  const ReservationAvailabilitySlot(
      {required this.time, required this.available});

  final DateTime time;
  final bool available;
}
