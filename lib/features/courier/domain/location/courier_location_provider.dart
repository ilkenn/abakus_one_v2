import 'courier_location_snapshot.dart';

/// Backend-neutral source of location readings for one courier device —
/// a future platform-specific implementation (e.g. wrapping a location
/// package) would sit behind this without the domain layer ever depending
/// on it. **No such implementation exists this phase** — no location
/// package is a dependency of this project; only [NoOpCourierLocationProvider]
/// ships, an honest "never produces a reading" default.
abstract interface class CourierLocationProvider {
  Stream<CourierLocationSnapshot> watch({
    required String courierId,
    required String deviceId,
  });
}

class NoOpCourierLocationProvider implements CourierLocationProvider {
  const NoOpCourierLocationProvider();

  @override
  Stream<CourierLocationSnapshot> watch({
    required String courierId,
    required String deviceId,
  }) =>
      const Stream.empty();
}
