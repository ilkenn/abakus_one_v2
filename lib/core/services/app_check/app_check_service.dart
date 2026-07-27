/// App Check activation — foundation only. This sprint prepares
/// application-side integration (environment-aware provider selection); it
/// does **not** enable Firebase Console enforcement, and nothing yet
/// consumes an App Check token (that's for the first feature that actually
/// calls a Firestore/Functions/Storage endpoint App Check protects).
///
/// Deliberately minimal: a single [initialize] entry point, matching how
/// `FirebaseAuthEmulatorConfig`/`FirebaseBootstrapService` scope their own
/// foundation-only work to policy, not full wiring, ahead of a real
/// consumer.
abstract interface class AppCheckService {
  /// Activates App Check for the current platform/environment. Never
  /// throws — any failure is caught, logged, and left as "not activated"
  /// so app startup is never blocked by App Check (mirrors
  /// [FirebaseBootstrapService]'s "never throws" contract).
  Future<void> initialize();
}
