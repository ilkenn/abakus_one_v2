import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The single storage seam for [HeroAbacus]'s once-per-launch teaser
/// rotation — deliberately narrow (read/advance one integer, nothing else)
/// and deliberately kept out of `hero_abacus.dart` itself, so the widget's
/// rendering/physics code never depends on persistence. Mirrors the house
/// pattern already established by `SessionStorage`/`SecureSessionStorage`
/// (`lib/features/auth/data/session_storage.dart`): interface + real
/// implementation + fail-safe on any error, injectable for tests.
abstract interface class HeroAbacusScenarioStore {
  /// The scenario to play next, always in `0..scenarioCount - 1`. Missing,
  /// corrupt, or out-of-range stored values fail safe to `0` rather than
  /// throwing or crashing Login's startup.
  Future<int> readScenarioIndex();

  /// Advances the rotation after the teaser identified by
  /// [justPlayedIndex] has finished playing — never called before that,
  /// so a launch that never finishes the teaser (e.g. the user navigates
  /// away first) replays the same scenario next time rather than skipping
  /// one. Wraps back to `0` after the last scenario.
  Future<void> persistNextScenarioIndex(int justPlayedIndex);
}

/// The real, `shared_preferences`-backed implementation. Stores exactly one
/// non-sensitive integer — no bead positions, no authentication data.
class SharedPreferencesHeroAbacusScenarioStore
    implements HeroAbacusScenarioStore {
  static const _key = 'heroAbacusScenarioIndex';

  /// Number of hand-authored teaser scenarios — kept in sync with
  /// `HeroAbacusScenarios.all.length` (see `hero_abacus_scenarios.dart`).
  static const int scenarioCount = 12;

  const SharedPreferencesHeroAbacusScenarioStore();

  @override
  Future<int> readScenarioIndex() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getInt(_key);
      if (value == null || value < 0 || value >= scenarioCount) return 0;
      return value;
    } catch (_) {
      return 0;
    }
  }

  @override
  Future<void> persistNextScenarioIndex(int justPlayedIndex) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final next = (justPlayedIndex + 1) % scenarioCount;
      await prefs.setInt(_key, next);
    } catch (_) {
      // Best-effort: worst case, the next launch replays the same
      // scenario instead of advancing — a safe failure mode, not a crash.
    }
  }
}

final heroAbacusScenarioStoreProvider = Provider<HeroAbacusScenarioStore>(
  (ref) => const SharedPreferencesHeroAbacusScenarioStore(),
);

/// Read once per app session (not `.watch`-friendly-volatile — the index is
/// only meant to change via [HeroAbacusScenarioStore.persistNextScenarioIndex]
/// after a teaser completes, not to react to itself).
final heroAbacusScenarioIndexProvider = FutureProvider<int>((ref) {
  return ref.watch(heroAbacusScenarioStoreProvider).readScenarioIndex();
});
