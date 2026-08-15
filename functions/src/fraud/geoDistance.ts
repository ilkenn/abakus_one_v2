/**
 * Pure great-circle distance — FRAUD-F.1. Used to compute
 * `ServerFraudInterpretation.distanceMeters` between a customer's selected
 * delivery coordinates and a device-location candidate. Same well-known
 * haversine formula already used client-side in
 * `lib/features/courier/domain/fraud/courier_fraud_signal_detector.dart`
 * (`_distanceMeters`) — reimplemented here in TypeScript since this
 * codebase has no shared Dart/TS code path (`CLAUDE.md`'s "no code
 * generation step").
 */

const EARTH_RADIUS_METERS = 6371000;

function toRadians(degrees: number): number {
  return (degrees * Math.PI) / 180;
}

export function distanceMeters(
  lat1: number,
  lon1: number,
  lat2: number,
  lon2: number,
): number {
  const dLat = toRadians(lat2 - lat1);
  const dLon = toRadians(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRadians(lat1)) *
      Math.cos(toRadians(lat2)) *
      Math.sin(dLon / 2) *
      Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return EARTH_RADIUS_METERS * c;
}
