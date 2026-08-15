import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'hero_abacus_geometry.dart';

/// A single meaningful impact — bead-vs-bead or bead-vs-edge — worth
/// possibly turning into haptic feedback. [speed] is the impact's relative
/// velocity in rod-fractions/second, used by the widget layer to classify
/// none/light/medium.
@immutable
class HeroAbacusImpact {
  final int row;
  final int col;
  final double speed;

  const HeroAbacusImpact({
    required this.row,
    required this.col,
    required this.speed,
  });
}

/// The Hero Abacus's physics core: every bead is a real particle at all
/// times (position + velocity), not just the one being touched. Pure Dart
/// state (`ChangeNotifier` only, no platform channels, no widget
/// dependency) — independently unit-testable, and kept separate from
/// rendering/gesture/haptics per the "geometry/state, physics, painting,
/// gesture handling, haptics" split.
///
/// **Direct manipulation while dragging**: [updateDrag] sets the active
/// bead's position literally 1:1 from the pointer — no tween, no easing,
/// no interpolation while the finger is down. Its velocity is only used as
/// an *estimate* (for collision impact strength and as the release
/// velocity), never to smooth the position itself.
///
/// **Physics on release / for pushed neighbors**: [step] integrates
/// position from velocity, applies time-based damping (frame-rate
/// independent), resolves bead-vs-bead collisions (low restitution,
/// momentum transferred to the neighbor rather than an instant clamp — a
/// fast push naturally propagates `A → B → C` over consecutive `step`
/// calls), and clamps at both rod ends (a small rebound only above a
/// "high velocity" threshold, otherwise a hard stop). A hard velocity
/// clamp and finite-value sanitation run at the end of every step, so the
/// system is guaranteed to never explode or reach a NaN/Infinity state
/// regardless of how it got there.
class HeroAbacusController extends ChangeNotifier {
  static const int rowCount = HeroAbacusGeometry.rowCount;
  static const int beadsPerRow = HeroAbacusGeometry.beadsPerRow;

  /// Fraction of velocity remaining after one second of free (undamped by
  /// collision) motion — frame-rate independent via `pow(decay, dt)`. Kept
  /// aggressive (high damping) so a typical release's visible residual
  /// motion is short, per the spec's "~120-300ms of visible residual
  /// motion... premium physical object, not pinball."
  static const double velocityDecayPerSecond = 0.0006;

  static const double restVelocityEpsilon = 0.02;

  /// Low restitution -- soft, non-bouncy hand-offs, per "low restitution,
  /// high damping."
  static const double restitution = 0.16;
  static const double edgeRestitution = 0.12;
  static const double highVelocityThreshold = 1.1;
  static const double maxVelocityFractionPerSecond = 6.0;
  static const double minRecordableImpact = 0.05;

  late List<List<double>> _positions;
  late List<List<double>> _velocities;

  HeroAbacusGeometry? _geometry;

  int? _draggingRow;
  int? _draggingCol;
  Duration? _lastDragTimestamp;
  double _dragVelocityEstimate = 0.0;

  final List<HeroAbacusImpact> _pendingImpacts = [];

  /// Debug/lab-only convenience state — persistent (not drained), safe to
  /// read at any time via a `Listenable` rebuild. Not used by `HeroAbacus`
  /// itself, which drains `_pendingImpacts` for haptics instead; exists so
  /// `HeroAbacusLabScreen`'s debug readout doesn't have to compete with
  /// that drain for the same events.
  double? lastReleaseSpeed;
  double lastImpactSpeed = 0.0;

  HeroAbacusController() {
    resetToRestingLayout();
  }

  /// Read-only from callers — mutated only through this controller's own
  /// methods (`step`, drag methods, `setBeadPositionDirect`).
  List<List<double>> get positions => _positions;
  List<List<double>> get velocities => _velocities;

  int? get draggingRow => _draggingRow;
  int? get draggingCol => _draggingCol;

  void updateGeometry(HeroAbacusGeometry geometry) {
    _geometry = geometry;
  }

  void resetToRestingLayout() {
    // Evenly spread, aligned across every row — see v1's design note:
    // "all beads begin centered, perfectly aligned" read as a clean grid,
    // not a packed cluster (packed beads would leave zero slack for a
    // teaser nudge without touching a third bead).
    _positions = List.generate(
      rowCount,
      (_) => List.generate(beadsPerRow, (col) => (col + 0.5) / beadsPerRow),
    );
    _velocities = List.generate(rowCount, (_) => List.filled(beadsPerRow, 0.0));
    notifyListeners();
  }

  bool get isSettled {
    if (_draggingRow != null) return false;
    for (final row in _velocities) {
      for (final v in row) {
        if (v.abs() > restVelocityEpsilon) return false;
      }
    }
    return true;
  }

  /// Drains and clears all impacts recorded since the last call — the
  /// widget layer polls this once per tick to decide on haptics.
  List<HeroAbacusImpact> drainImpacts() {
    if (_pendingImpacts.isEmpty) return const [];
    final drained = List<HeroAbacusImpact>.of(_pendingImpacts);
    _pendingImpacts.clear();
    return drained;
  }

  (int, int)? hitTest(Offset local) {
    final geometry = _geometry;
    if (geometry == null) return null;
    return geometry.hitTestBead(local, _positions);
  }

  void beginDrag(int row, int col, Duration timestamp) {
    _draggingRow = row;
    _draggingCol = col;
    _lastDragTimestamp = timestamp;
    _dragVelocityEstimate = 0.0;
    _velocities[row][col] = 0.0;
  }

  /// Sets the dragged bead's position directly from the pointer — literal
  /// 1:1, no smoothing, no easing — *unless* neighboring beads physically
  /// block it, in which case it's clamped to the furthest point reachable
  /// without any bead passing through another (beads may never overlap,
  /// full stop, even transiently mid-drag). [localX] is in the same pixel
  /// space as [HeroAbacusGeometry.rodInnerLeft]/`usableLength`.
  void updateDrag(double localX, Duration timestamp) {
    final row = _draggingRow;
    final col = _draggingCol;
    final geometry = _geometry;
    if (row == null || col == null || geometry == null) return;

    final minSep = geometry.minSeparationFraction;
    // The absolute furthest this bead could ever reach in either
    // direction, if every bead between it and that edge were fully
    // compressed against the edge -- computed from bead *count*, not
    // current positions, so it's always a valid bound regardless of where
    // the rest of the chain actually is right now. Clamping to this
    // range up front guarantees left-to-right array order can never be
    // violated, even transiently, which is what the relaxation pass
    // below depends on.
    final minReachable = col * minSep;
    final maxReachable = 1.0 - (beadsPerRow - 1 - col) * minSep;

    final newFraction =
        geometry.fractionForLocalX(localX).clamp(minReachable, maxReachable);
    final previous = _positions[row][col];
    final lastTimestamp = _lastDragTimestamp;
    final dtSeconds = lastTimestamp == null
        ? 1 / 60
        : math.max(
            (timestamp - lastTimestamp).inMicroseconds / 1e6,
            1 / 240,
          );
    _lastDragTimestamp = timestamp;

    final instantVelocity = (newFraction - previous) / dtSeconds;
    _dragVelocityEstimate = _dragVelocityEstimate == 0.0
        ? instantVelocity
        : (_dragVelocityEstimate * 0.7 + instantVelocity * 0.3);

    _positions[row][col] = newFraction;
    // Edge boundaries are resolved first, then neighbor spacing cascades
    // inward from those now-fixed boundary positions -- resolving
    // neighbors first and clamping edges after would leave an already-
    // correctly-spaced neighbor now too close to the edge bead's new,
    // clamped position.
    _clampEdges(row);
    _resolveRowConstraints(row, dtSeconds);
    _sanitizeRow(row);
    notifyListeners();
  }

  void endDrag() {
    final row = _draggingRow;
    final col = _draggingCol;
    if (row == null || col == null) return;
    lastReleaseSpeed = _dragVelocityEstimate;
    _velocities[row][col] = _dragVelocityEstimate.clamp(
      -maxVelocityFractionPerSecond,
      maxVelocityFractionPerSecond,
    );
    _draggingRow = null;
    _draggingCol = null;
    _lastDragTimestamp = null;
    notifyListeners();
  }

  void cancelDrag() {
    _draggingRow = null;
    _draggingCol = null;
    _lastDragTimestamp = null;
    _dragVelocityEstimate = 0.0;
  }

  /// Directly overrides one bead's position (used only by the teaser's
  /// scripted micro-animation) without engaging drag state.
  void setBeadPositionDirect(int row, int col, double fraction) {
    _positions[row][col] = fraction.clamp(0.0, 1.0);
    notifyListeners();
  }

  /// Test-only seam: seeds a bead's position and/or velocity directly,
  /// bypassing drag state entirely — lets physics tests (chain collision,
  /// edge impact, settling behavior) start from a precise, deterministic
  /// state instead of reverse-engineering it through synthetic drag
  /// gestures. Never used by production code.
  @visibleForTesting
  void debugSetState(int row, int col, {double? position, double? velocity}) {
    if (position != null) _positions[row][col] = position;
    if (velocity != null) _velocities[row][col] = velocity;
  }

  /// Advances the simulation by [dtSeconds]. Safe to call every frame
  /// regardless of whether anything is actually moving — `isSettled`
  /// tells the caller when it's safe to stop ticking.
  void step(double dtSeconds) {
    if (_geometry == null || dtSeconds <= 0) return;
    final decay = math.pow(velocityDecayPerSecond, dtSeconds).toDouble();

    for (var row = 0; row < rowCount; row++) {
      final pos = _positions[row];
      final vel = _velocities[row];
      for (var col = 0; col < beadsPerRow; col++) {
        if (row == _draggingRow && col == _draggingCol) continue;
        if (vel[col] == 0.0) continue;
        pos[col] += vel[col] * dtSeconds;
        vel[col] *= decay;
        if (vel[col].abs() < restVelocityEpsilon) vel[col] = 0.0;
      }
      _clampEdges(row);
      _resolveRowConstraints(row, dtSeconds);
      _sanitizeRow(row);
    }
    notifyListeners();
  }

  bool _isDragged(int row, int col) =>
      row == _draggingRow && col == _draggingCol;

  void _recordImpact(int row, int col, double speed) {
    if (speed < minRecordableImpact) return;
    lastImpactSpeed = speed;
    _pendingImpacts.add(HeroAbacusImpact(row: row, col: col, speed: speed));
  }

  /// Sequential push-relaxation, augmented with velocity transfer: when a
  /// bead is displaced to resolve an overlap, it's given a velocity
  /// derived from how hard it was hit (bounded, restitution-scaled) rather
  /// than just being teleported — this is what lets `A → B → C` chain
  /// pushes emerge over consecutive `step` calls instead of being a flat
  /// instant clamp.
  void _resolveRowConstraints(int row, double dt) {
    final pos = _positions[row];
    final vel = _velocities[row];
    final minSep = _geometry!.minSeparationFraction;

    void push(int index, double rawNewPos, int fromNeighbor) {
      // The actively-dragged bead's position is authoritative (already
      // clamped to a reachable value in updateDrag) -- the solver must
      // never reposition it, only the beads around it.
      if (_isDragged(row, index)) return;

      // Never push a bead (interior or boundary) past the rod's own
      // [0,1] bounds -- without this, a chain that's already compressed
      // against the edge can be assigned a push target just past 1.0/0.0
      // every frame, which (since edge-clamping and this relaxation run
      // in separate steps) would hand that boundary bead a fresh non-zero
      // "impact" velocity every single frame even though it's not
      // actually moving, growing without bound.
      final newPos = rawNewPos.clamp(0.0, 1.0);

      final oldPos = pos[index];
      final displacement = newPos - oldPos;
      // Ignores floating-point-noise-level "corrections" (accumulated
      // from chained additions elsewhere in this pass) -- without this, a
      // near-zero spurious displacement would still overwrite a bead's
      // real velocity with a near-zero impact speed, silently killing its
      // own momentum.
      if (displacement.abs() < 1e-9) return;
      pos[index] = newPos;

      final neighborSpeed = vel[fromNeighbor].abs();
      final impliedSpeed = displacement.abs() / dt;
      final impactSpeed = math.min(
        math.max(neighborSpeed, impliedSpeed),
        maxVelocityFractionPerSecond,
      );
      vel[index] = displacement.isNegative
          ? -impactSpeed * restitution
          : impactSpeed * restitution;
      _recordImpact(row, index, impactSpeed);
    }

    for (var i = 1; i < pos.length; i++) {
      final minAllowed = pos[i - 1] + minSep;
      if (pos[i] < minAllowed) push(i, minAllowed, i - 1);
    }
    for (var i = pos.length - 2; i >= 0; i--) {
      final maxAllowed = pos[i + 1] - minSep;
      if (pos[i] > maxAllowed) push(i, maxAllowed, i + 1);
    }
    // A second left-to-right pass catches overlaps the right-to-left pass
    // could reintroduce -- keeps a tightly packed rod stable.
    for (var i = 1; i < pos.length; i++) {
      final minAllowed = pos[i - 1] + minSep;
      if (pos[i] < minAllowed) push(i, minAllowed, i - 1);
    }
  }

  void _clampEdges(int row) {
    final pos = _positions[row];
    final vel = _velocities[row];

    if (pos.first < 0.0) {
      final impactSpeed = vel.first.abs();
      pos[0] = 0.0;
      if (!_isDragged(row, 0)) {
        vel[0] = impactSpeed > highVelocityThreshold
            ? impactSpeed * edgeRestitution
            : 0.0;
        _recordImpact(row, 0, impactSpeed);
      }
    }
    final last = pos.length - 1;
    if (pos[last] > 1.0) {
      final impactSpeed = vel[last].abs();
      pos[last] = 1.0;
      if (!_isDragged(row, last)) {
        vel[last] = impactSpeed > highVelocityThreshold
            ? -impactSpeed * edgeRestitution
            : 0.0;
        _recordImpact(row, last, impactSpeed);
      }
    }
  }

  /// Hard safety net: regardless of how the solver got here, no bead may
  /// ever end this row's update at a non-finite value or outside its
  /// valid range, and no velocity may exceed the hard cap.
  void _sanitizeRow(int row) {
    final pos = _positions[row];
    final vel = _velocities[row];
    for (var col = 0; col < beadsPerRow; col++) {
      if (!pos[col].isFinite) {
        pos[col] = (col + 0.5) / beadsPerRow;
      }
      pos[col] = pos[col].clamp(0.0, 1.0);
      if (!vel[col].isFinite) {
        vel[col] = 0.0;
      }
      vel[col] = vel[col].clamp(
        -maxVelocityFractionPerSecond,
        maxVelocityFractionPerSecond,
      );
    }
  }
}
