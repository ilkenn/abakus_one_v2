import 'reservation_area.dart';

/// The server-authoritative snapshot `getReservationBranchInfo` returns —
/// everything the first two flow steps (party size bounds, area
/// selection) need, and nothing else (no capacity/occupancy data, no
/// internal ids beyond an area's own `id`/`displayName`).
class ReservationBranchPolicy {
  const ReservationBranchPolicy({
    required this.maxPartySize,
    required this.slotIntervalMinutes,
    required this.reservationDurationMinutes,
    required this.bookingHorizonDays,
    required this.timezone,
    required this.minimumAdvanceMinutes,
  });

  final int maxPartySize;
  final int slotIntervalMinutes;
  final int reservationDurationMinutes;
  final int bookingHorizonDays;
  final String timezone;
  final int minimumAdvanceMinutes;
}

class ReservationBranchInfo {
  const ReservationBranchInfo({required this.policy, required this.areas});

  final ReservationBranchPolicy policy;
  final List<ReservationArea> areas;
}
