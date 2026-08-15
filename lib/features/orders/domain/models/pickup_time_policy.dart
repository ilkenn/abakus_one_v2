/// The minimum-lead-time rule for a `PickupMode.scheduled` takeaway
/// pickup — Faz C (Gel Al authenticated in-app ordering).
///
/// Pure duration arithmetic: comparing two instants ([pickupTime]/[now])
/// is timezone-invariant, so this needs no timezone-aware library —
/// "Europe/Istanbul" (this app's only branch timezone, `Branch.timezone`)
/// only matters for how a pickup time is *displayed*, never for whether
/// it satisfies the minimum-lead-time rule itself. Turkey has used a
/// permanent UTC+3 offset with no DST since 2016, so a fixed `+3:00`
/// offset is safe to use for display formatting without depending on the
/// `timezone` package.
///
/// **Client-side use only.** The authoritative check is
/// `firestore.rules`' `isValidAuthenticatedTakeawayOrder()`, which
/// compares the same boundary against `request.time` (the server's own
/// clock) — this class exists so the UI can show/reject an obviously
/// invalid selection immediately, without waiting on a round trip, but a
/// manipulated device clock can only fool *this* check, never the
/// server-side one.
abstract final class PickupTimePolicy {
  PickupTimePolicy._();

  static const Duration minimumLeadTime = Duration(minutes: 20);

  /// The earliest instant a `scheduled` pickup may be set to, given [now].
  static DateTime minimumPickupTime(DateTime now) => now.add(minimumLeadTime);

  /// Whether [pickupTime] satisfies the minimum-lead-time rule relative to
  /// [now] — inclusive of the exact boundary (`now + 20:00` is valid,
  /// `now + 19:59` is not).
  static bool isValid(DateTime pickupTime, DateTime now) {
    return !pickupTime.isBefore(minimumPickupTime(now));
  }

  /// Turkey's fixed UTC+3 offset (Europe/Istanbul, no DST since 2016) —
  /// for display formatting only, never for the [isValid] comparison
  /// itself (which is timezone-invariant).
  static const Duration istanbulUtcOffset = Duration(hours: 3);
}
