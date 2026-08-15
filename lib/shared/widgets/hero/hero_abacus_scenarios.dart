/// One bead's part in a teaser scenario: which bead (by its resting
/// row/column) moves, how far (a signed fraction of the rod's usable
/// travel — small, per the "very short" requirement, and deliberately kept
/// well under half the resting gap between evenly-spaced beads so a teaser
/// move never touches a neighboring bead: only the two named beads move,
/// nothing else reacts), and how slowly.
class HeroAbacusTeaserMove {
  final int row;
  final int column;
  final double offsetFraction;
  final Duration duration;

  const HeroAbacusTeaserMove({
    required this.row,
    required this.column,
    required this.offsetFraction,
    required this.duration,
  });
}

/// A single once-per-launch teaser: exactly two beads move, [first] then
/// [second] — never simultaneously — each sliding out a short distance and
/// gently back to its resting position, then stopping forever.
class HeroAbacusScenario {
  final HeroAbacusTeaserMove first;
  final HeroAbacusTeaserMove second;

  const HeroAbacusScenario({required this.first, required this.second});
}

/// The 12 hand-authored teaser scenarios, rotated sequentially (never
/// randomly) across app launches by [HeroAbacusScenarioStore] — index `n`
/// always means `all[n]`, so this list's order and length (kept in sync
/// with `SharedPreferencesHeroAbacusScenarioStore.scenarioCount`) must
/// never change without updating that constant too.
///
/// Rows/columns are 0-indexed (row 0 = warm cream, ... row 5 = warm
/// mustard; column 0 = the rod's left end). Distances and durations are
/// deliberately varied per scenario so the rotation doesn't read as
/// mechanically repeated, while every one stays within the spec's "very
/// short, slow, elegant" bounds.
abstract final class HeroAbacusScenarios {
  HeroAbacusScenarios._();

  static const List<HeroAbacusScenario> all = [
    HeroAbacusScenario(
      first: HeroAbacusTeaserMove(
        row: 1,
        column: 2,
        offsetFraction: 0.032,
        duration: Duration(milliseconds: 1100),
      ),
      second: HeroAbacusTeaserMove(
        row: 4,
        column: 3,
        offsetFraction: -0.027,
        duration: Duration(milliseconds: 1000),
      ),
    ),
    HeroAbacusScenario(
      first: HeroAbacusTeaserMove(
        row: 0,
        column: 4,
        offsetFraction: -0.036,
        duration: Duration(milliseconds: 950),
      ),
      second: HeroAbacusTeaserMove(
        row: 3,
        column: 1,
        offsetFraction: 0.027,
        duration: Duration(milliseconds: 1150),
      ),
    ),
    HeroAbacusScenario(
      first: HeroAbacusTeaserMove(
        row: 5,
        column: 0,
        offsetFraction: 0.04,
        duration: Duration(milliseconds: 1050),
      ),
      second: HeroAbacusTeaserMove(
        row: 2,
        column: 5,
        offsetFraction: -0.032,
        duration: Duration(milliseconds: 1000),
      ),
    ),
    HeroAbacusScenario(
      first: HeroAbacusTeaserMove(
        row: 2,
        column: 2,
        offsetFraction: -0.027,
        duration: Duration(milliseconds: 1000),
      ),
      second: HeroAbacusTeaserMove(
        row: 5,
        column: 4,
        offsetFraction: 0.036,
        duration: Duration(milliseconds: 1100),
      ),
    ),
    HeroAbacusScenario(
      first: HeroAbacusTeaserMove(
        row: 3,
        column: 5,
        offsetFraction: 0.032,
        duration: Duration(milliseconds: 1200),
      ),
      second: HeroAbacusTeaserMove(
        row: 0,
        column: 1,
        offsetFraction: -0.023,
        duration: Duration(milliseconds: 950),
      ),
    ),
    HeroAbacusScenario(
      first: HeroAbacusTeaserMove(
        row: 4,
        column: 0,
        offsetFraction: -0.04,
        duration: Duration(milliseconds: 1050),
      ),
      second: HeroAbacusTeaserMove(
        row: 1,
        column: 3,
        offsetFraction: 0.027,
        duration: Duration(milliseconds: 1000),
      ),
    ),
    HeroAbacusScenario(
      first: HeroAbacusTeaserMove(
        row: 0,
        column: 3,
        offsetFraction: 0.027,
        duration: Duration(milliseconds: 1000),
      ),
      second: HeroAbacusTeaserMove(
        row: 4,
        column: 5,
        offsetFraction: -0.036,
        duration: Duration(milliseconds: 1100),
      ),
    ),
    HeroAbacusScenario(
      first: HeroAbacusTeaserMove(
        row: 5,
        column: 2,
        offsetFraction: -0.032,
        duration: Duration(milliseconds: 950),
      ),
      second: HeroAbacusTeaserMove(
        row: 2,
        column: 0,
        offsetFraction: 0.04,
        duration: Duration(milliseconds: 1150),
      ),
    ),
    HeroAbacusScenario(
      first: HeroAbacusTeaserMove(
        row: 1,
        column: 5,
        offsetFraction: 0.036,
        duration: Duration(milliseconds: 1050),
      ),
      second: HeroAbacusTeaserMove(
        row: 3,
        column: 2,
        offsetFraction: -0.027,
        duration: Duration(milliseconds: 1000),
      ),
    ),
    HeroAbacusScenario(
      first: HeroAbacusTeaserMove(
        row: 2,
        column: 4,
        offsetFraction: -0.027,
        duration: Duration(milliseconds: 1000),
      ),
      second: HeroAbacusTeaserMove(
        row: 5,
        column: 1,
        offsetFraction: 0.032,
        duration: Duration(milliseconds: 1100),
      ),
    ),
    HeroAbacusScenario(
      first: HeroAbacusTeaserMove(
        row: 3,
        column: 0,
        offsetFraction: 0.04,
        duration: Duration(milliseconds: 1150),
      ),
      second: HeroAbacusTeaserMove(
        row: 0,
        column: 2,
        offsetFraction: -0.032,
        duration: Duration(milliseconds: 950),
      ),
    ),
    HeroAbacusScenario(
      first: HeroAbacusTeaserMove(
        row: 4,
        column: 4,
        offsetFraction: -0.036,
        duration: Duration(milliseconds: 1000),
      ),
      second: HeroAbacusTeaserMove(
        row: 1,
        column: 1,
        offsetFraction: 0.027,
        duration: Duration(milliseconds: 1050),
      ),
    ),
  ];
}
