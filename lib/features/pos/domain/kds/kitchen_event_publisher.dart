import 'kitchen_event.dart';

/// Publishes a [KitchenEvent] to every interested subscriber —
/// backend-neutral by design, so a future Firebase (Firestore listeners,
/// Realtime Database, or a Cloud Functions-fronted push channel)
/// implementation can sit behind this contract without the domain layer
/// ever importing `firebase_*` (`CLAUDE.md` §5 — Firebase remains
/// present-but-dormant; wiring a real implementation is a separate,
/// explicitly-approved architecture change, not bundled into this phase).
///
/// **This phase ships only an in-memory implementation** —
/// `InMemoryKitchenEventBus` — which fans events out to same-process
/// listeners only. It provides ordered, at-least-once delivery *within
/// one running app instance*; it is **not** a substitute for real
/// cross-device/cross-process real-time infrastructure, which does not
/// exist in this codebase (see `docs/decisions.md` ADR-016 for the
/// honestly-reported boundary).
abstract interface class KitchenEventPublisher {
  Future<void> publish(KitchenEvent event);
}
