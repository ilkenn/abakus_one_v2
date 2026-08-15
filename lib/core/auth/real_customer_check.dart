import '../../features/auth/presentation/providers/auth_provider.dart';

/// Whether [authState] represents a real, phone-verified, non-expired
/// Abaküs customer — never a guest, never merely "some Firebase Auth
/// session exists." Promoted to `core/auth` (Faz R.2, D3) from its
/// original home in `features/takeaway/domain/real_customer_check.dart`
/// once a second feature (`reservation`) needed the identical check —
/// this codebase's own established "second consumer promotes a thing to
/// shared" convention, applied here to a small domain predicate rather
/// than a widget. Every call site (takeaway's entry gate + submit-time
/// backstop, reservation's route guard + entry gate) shares this exact
/// function, never an independently-maintained copy.
bool isRealCustomer(AuthState authState) {
  final session = authState.session;
  return authState.isAuthenticated &&
      !authState.isGuest &&
      session != null &&
      !session.isExpired;
}
