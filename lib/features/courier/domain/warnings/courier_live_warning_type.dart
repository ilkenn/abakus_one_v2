/// A manager-facing live operational warning — Sprint 5C Part 9.
/// **Every value here is a projection over an existing Sprint 5B/5C
/// signal, never a new detector**: [gpsDisabled]/[noLocationUpdates] read
/// `CourierLocationAvailability`/`CourierLiveStatus`, [courierOffline]
/// reads `CourierLiveStatus.isOnline` (`CourierConnectionMonitor`),
/// [abnormalRoute]/[operationalRisk] read `CourierFraudSignal`, and
/// [longInactivity] reads `CourierLiveStatus.movementState`/
/// `lastLocationUpdateAt`. `BuildCourierLiveWarnings` only aggregates and
/// surfaces them — it introduces no new detection logic.
enum CourierLiveWarningType {
  gpsDisabled,
  courierOffline,
  noLocationUpdates,
  abnormalRoute,
  longInactivity,
  operationalRisk,
}
