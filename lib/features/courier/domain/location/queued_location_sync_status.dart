/// Outcome of attempting to sync one locally-queued [CourierLocationSnapshot]
/// — Sprint 5B Part 7. Mirrors `PendingCourierCommandStatus`'s shape,
/// deliberately without a `conflict` value: an immutable location reading
/// has no revision to be stale against — there is nothing to conflict
/// with, only "already recorded" (handled by [CourierLocationRepository
/// .containsId] deduplication, never surfaced as its own state).
enum QueuedLocationSyncStatus { pending, synced, failed }
