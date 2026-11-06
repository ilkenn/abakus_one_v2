/// App-wide literal constants with no natural home in a more specific
/// config file (`core/config/app_environment_config.dart` covers values
/// that actually vary by environment) — simple, non-secret values any
/// feature may need are added here.
class AppConstants {
  const AppConstants._();

  /// Self-Order QR Faz 6 (23-rule plan §8, "Kapanış + Google review") —
  /// the restaurant's Google Business Profile review link, opened from
  /// [TableContextBadge] once a table visit ends. **Deliberately `null`**:
  /// there is no real Google Business Profile review URL recorded anywhere
  /// in this codebase to source it from (confirmed by a repo-wide search),
  /// and CLAUDE.md forbids fabricating business data such as a guessed
  /// link. Every call site treats `null` as "don't show the review
  /// prompt" — never as a broken or placeholder link shown to a real
  /// customer. Set this to the real review URL (e.g.
  /// `https://g.page/r/<id>/review`) once it's available; no other code
  /// change is needed for the prompt to start appearing.
  static const String? googleReviewUrl = null;
}
