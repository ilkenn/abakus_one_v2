/// Backend/platform-neutral seam for a background-location tracking
/// session — "background-location production deployment" is explicitly
/// out of scope this phase; [NoOpBackgroundLocationSession] is an honest
/// "never actually tracks" default, present so calling code has a real
/// seam to depend on once platform support is added.
abstract interface class BackgroundLocationSession {
  Future<void> start({required String courierId, required String deviceId});
  Future<void> stop({required String courierId, required String deviceId});
  bool get isActive;
}

class NoOpBackgroundLocationSession implements BackgroundLocationSession {
  bool _active = false;

  @override
  Future<void> start({
    required String courierId,
    required String deviceId,
  }) async {
    _active = false; // never actually starts — honest no-op
  }

  @override
  Future<void> stop({
    required String courierId,
    required String deviceId,
  }) async {
    _active = false;
  }

  @override
  bool get isActive => _active;
}
