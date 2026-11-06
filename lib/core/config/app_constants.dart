/// App-wide literal constants with no natural home in a more specific
/// config file (`core/config/app_environment_config.dart` covers values
/// that actually vary by environment) — simple, non-secret values any
/// feature may need are added here.
class AppConstants {
  const AppConstants._();

  /// Self-Order QR Faz 6 (23-rule plan §8, "Kapanış + Google review") —
  /// the restaurant's Google Business Profile review link, opened from
  /// [TableContextBadge] once a table visit ends.
  ///
  /// **2026-11-06, explicit user instruction**: set to this placeholder
  /// value directly by the user ("yer tutucu olarak... bağlayıp
  /// url_launcher tıklandığında açılacak şekilde hazır tutalım") — not a
  /// value this codebase guessed or fabricated. The user has acknowledged
  /// this is a placeholder, not yet the business's real, verified review
  /// deep link; replace it with the real one (from the business's Google
  /// Business Profile "Ask for reviews" link, or a real `g.page/r/<id>
  /// /review` short link) whenever that's available — no other code
  /// change is needed for the prompt to keep working once it's swapped.
  static const String? googleReviewUrl = 'https://g.page/r/resto-menum/review';
}
