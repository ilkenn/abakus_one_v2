/// One completed leg's actual distance/duration — the raw input to
/// [HistoricalEtaAverageCalculator]. Callers assemble these from past
/// [DeliveryRouteSnapshot]/geofence-arrival data; this type itself has no
/// opinion on where they came from.
class EtaHistoricalSample {
  const EtaHistoricalSample({
    required this.distanceMeters,
    required this.actualDurationSeconds,
  });

  final double distanceMeters;
  final double actualDurationSeconds;
}
