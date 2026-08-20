/// Customer Registration CR.1 — the four states the post-OTP routing gate
/// (and the "Profilini Tamamla" screen's own top-level render) must be
/// able to distinguish, per the locked routing spec: a real customer's
/// canonical registration is still resolving ([loading]), fully done
/// ([complete]), missing/partial ([incomplete]), or unreachable
/// ([error]) — the last three all keep the customer off `/main`, but each
/// renders a different UI ("resolving your account…" vs. the form vs. a
/// retry view).
enum CustomerProfileCompletionPhase { loading, complete, incomplete, error }

/// A typed result, not a nullable bool — [phase] alone is what
/// `AppRouteGuard`-adjacent routing logic needs (see `customer_registration_providers.dart`,
/// which reduces this to a plain `bool needsProfileCompletion` before it
/// ever reaches the feature-agnostic `core/router/app_route_guard.dart`);
/// [errorMessage] exists purely for the completion screen's own retry UI.
class CustomerProfileCompletionState {
  const CustomerProfileCompletionState._(this.phase, this.errorMessage);

  const CustomerProfileCompletionState.loading()
      : this._(CustomerProfileCompletionPhase.loading, null);
  const CustomerProfileCompletionState.complete()
      : this._(CustomerProfileCompletionPhase.complete, null);
  const CustomerProfileCompletionState.incomplete()
      : this._(CustomerProfileCompletionPhase.incomplete, null);
  const CustomerProfileCompletionState.error([String? message])
      : this._(CustomerProfileCompletionPhase.error, message);

  final CustomerProfileCompletionPhase phase;
  final String? errorMessage;

  bool get isComplete => phase == CustomerProfileCompletionPhase.complete;

  @override
  bool operator ==(Object other) =>
      other is CustomerProfileCompletionState &&
      other.phase == phase &&
      other.errorMessage == errorMessage;

  @override
  int get hashCode => Object.hash(phase, errorMessage);

  @override
  String toString() =>
      'CustomerProfileCompletionState(${phase.name}${errorMessage != null ? ', $errorMessage' : ''})';
}
