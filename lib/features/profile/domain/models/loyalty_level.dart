/// A sadakat (loyalty) tier, derived from [LoyaltyState.currentBalance] —
/// never stored independently, so it can never drift out of sync with the
/// balance it's computed from.
enum LoyaltyLevel { bronze, silver, gold }

/// Tier thresholds and display helpers for [LoyaltyLevel].
///
/// Single source of truth for "how many Boncuk does each tier need" — every
/// screen that shows a level or a level-progress bar (Home, Loyalty) reads
/// through this instead of hardcoding its own thresholds.
abstract final class LoyaltyLevelInfo {
  LoyaltyLevelInfo._();

  static const Map<LoyaltyLevel, int> _thresholds = {
    LoyaltyLevel.bronze: 0,
    LoyaltyLevel.silver: 1000,
    LoyaltyLevel.gold: 3000,
  };

  /// The tier [balance] currently falls into.
  static LoyaltyLevel forBalance(int balance) {
    if (balance >= _thresholds[LoyaltyLevel.gold]!) return LoyaltyLevel.gold;
    if (balance >= _thresholds[LoyaltyLevel.silver]!) {
      return LoyaltyLevel.silver;
    }
    return LoyaltyLevel.bronze;
  }

  /// The minimum balance required to reach [level].
  static int thresholdFor(LoyaltyLevel level) => _thresholds[level]!;

  /// The tier after [level], or `null` if [level] is already the highest.
  static LoyaltyLevel? next(LoyaltyLevel level) {
    switch (level) {
      case LoyaltyLevel.bronze:
        return LoyaltyLevel.silver;
      case LoyaltyLevel.silver:
        return LoyaltyLevel.gold;
      case LoyaltyLevel.gold:
        return null;
    }
  }

  /// Turkish display label for [level].
  static String labelFor(LoyaltyLevel level) {
    switch (level) {
      case LoyaltyLevel.bronze:
        return 'Bronz Seviye';
      case LoyaltyLevel.silver:
        return 'Gümüş Seviye';
      case LoyaltyLevel.gold:
        return 'Altın Seviye';
    }
  }
}
