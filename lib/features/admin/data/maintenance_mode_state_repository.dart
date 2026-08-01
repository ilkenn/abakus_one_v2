import '../domain/system/maintenance_mode_state.dart';

/// Storage for the single, system-wide [MaintenanceModeState] — a true
/// singleton, unlike every other repository in this codebase (Phase 6O,
/// `docs/decisions.md` ADR-023).
abstract interface class MaintenanceModeStateRepository {
  Future<MaintenanceModeState?> find();
  Future<void> save(MaintenanceModeState state);
}

class InMemoryMaintenanceModeStateRepository
    implements MaintenanceModeStateRepository {
  MaintenanceModeState? _state;

  @override
  Future<MaintenanceModeState?> find() async => _state;

  @override
  Future<void> save(MaintenanceModeState state) async => _state = state;
}
