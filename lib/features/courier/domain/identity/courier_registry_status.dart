/// Registry-level status of a [Courier] — independent of shift/availability
/// status (a courier can be `active` in the registry while off-shift).
enum CourierRegistryStatus { active, suspended, archived }
