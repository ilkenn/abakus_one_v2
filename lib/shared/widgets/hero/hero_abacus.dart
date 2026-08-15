import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'hero_abacus_controller.dart';
import 'hero_abacus_geometry.dart';
import 'hero_abacus_painter.dart';
import 'hero_abacus_scenarios.dart';

/// The ABAKÜS signature object — a horizontal, 6-rod/36-bead abacus with
/// real drag/collision/inertia physics and a once-per-launch teaser
/// micro-animation (currently disabled — see [_HeroAbacusState]
/// `_teaserTemporarilyDisabled`). Built as an independent, reusable
/// `shared/` component per the product spec.
///
/// **Rendering/interaction architecture (v2 rebuild)**: a single
/// [HeroAbacusController] (`hero_abacus_controller.dart`) owns all physics
/// state as a real particle system and is the sole source of truth; a
/// single [HeroAbacusPainter] (`hero_abacus_painter.dart`) paints the
/// entire object every repaint, driven directly by the controller's
/// `notifyListeners()` — no `setState`, no per-bead widgets, no widget
/// rebuild during interaction. Gestures are handled with a raw [Listener]
/// (not `GestureDetector`), removing gesture-arena disambiguation latency
/// so a drag tracks the finger with no perceptible lag. Everything lives
/// inside one [RepaintBoundary], so dragging a bead never repaints
/// anything outside this widget's own subtree.
///
/// Contains **no authentication logic and no persistence** —
/// [scenarioIndex] is supplied by the caller (see
/// `hero_abacus_scenario_store.dart`, kept in a separate file specifically
/// so this widget never imports `shared_preferences`), and
/// [onIntroAnimationComplete] only reports that the teaser finished.
class HeroAbacus extends StatefulWidget {
  /// The rendered width; height derives from a fixed internal aspect ratio
  /// ([HeroAbacusGeometry.aspectRatio]) so the object always scales
  /// uniformly, like a real physical item.
  final double width;

  /// When false, beads are purely decorative (no drag, no teaser).
  final bool interactive;

  /// Which of the 12 hand-authored teaser scenarios to play once, 0..11.
  /// Currently inert — see `_teaserTemporarilyDisabled`.
  final int scenarioIndex;

  /// Fired once, after the teaser scenario finishes playing. Currently
  /// never fires — see `_teaserTemporarilyDisabled`.
  final VoidCallback? onIntroAnimationComplete;

  /// Optional external controller — when supplied, `HeroAbacus` uses it
  /// instead of creating its own (and does not dispose it). Exists solely
  /// so `HeroAbacusLabScreen`'s debug readout can observe the exact same
  /// physics state (active bead, release/impact speed) this widget is
  /// rendering, without this widget knowing anything about debug UI.
  /// `LoginScreen` and every other real caller should leave this null.
  final HeroAbacusController? controller;

  const HeroAbacus({
    super.key,
    required this.width,
    this.interactive = true,
    this.scenarioIndex = 0,
    this.onIntroAnimationComplete,
    this.controller,
  });

  @override
  State<HeroAbacus> createState() => _HeroAbacusState();
}

enum _ImpactStrength { none, light, medium }

class _HeroAbacusState extends State<HeroAbacus> with TickerProviderStateMixin {
  /// Hero Abacus Lab v2 is scoped to touch/movement/collision/inertia/
  /// haptics/material realism first, per that task's explicit priority
  /// order — the 12-scenario teaser is deliberately not being worked on
  /// this pass. Flip this one constant back to `false` to restore it once
  /// physics/visuals pass real-device review; `HeroAbacusScenarios`/
  /// `HeroAbacusScenarioStore` are untouched and ready for that.
  static const bool _teaserTemporarilyDisabled = true;

  static const double _lightImpactThreshold = 0.35;
  static const double _mediumImpactThreshold = 0.9;
  static const Duration _hapticCooldown = Duration(milliseconds: 120);

  late final HeroAbacusController _controller;
  late final bool _ownsController;
  late final Ticker _ticker;
  Duration? _lastTick;

  int? _activePointer;
  Timer? _teaserTimer;
  final List<AnimationController> _teaserControllers = [];
  bool _reduceMotion = false;
  DateTime? _lastHapticAt;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? HeroAbacusController();
    _ownsController = widget.controller == null;
    _ticker = createTicker(_onTick);
    _reduceMotion = WidgetsBinding
        .instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    if (widget.interactive && !_reduceMotion && !_teaserTemporarilyDisabled) {
      _teaserTimer = Timer(const Duration(milliseconds: 900), _playTeaser);
    }
  }

  @override
  void dispose() {
    _teaserTimer?.cancel();
    for (final controller in _teaserControllers) {
      controller.dispose();
    }
    _ticker.dispose();
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  // ---- Physics tick ----------------------------------------------------

  void _onTick(Duration elapsed) {
    final last = _lastTick;
    _lastTick = elapsed;
    final rawDt = last == null ? 1 / 60 : (elapsed - last).inMicroseconds / 1e6;
    // Guards against a huge dt after the ticker had been paused/backgrounded.
    final dt = rawDt.clamp(1 / 240, 1 / 15);
    _controller.step(dt);

    final impacts = _controller.drainImpacts();
    if (impacts.isNotEmpty) {
      var maxSpeed = 0.0;
      for (final impact in impacts) {
        if (impact.speed > maxSpeed) maxSpeed = impact.speed;
      }
      _maybeTriggerHaptic(maxSpeed);
    }

    if (_activePointer == null && _controller.isSettled) {
      _ticker.stop();
    }
  }

  void _startTicking() {
    _lastTick = null;
    if (!_ticker.isTicking) _ticker.start();
  }

  _ImpactStrength _classifyImpact(double speed) {
    if (speed < _lightImpactThreshold) return _ImpactStrength.none;
    if (speed < _mediumImpactThreshold) return _ImpactStrength.light;
    return _ImpactStrength.medium;
  }

  void _maybeTriggerHaptic(double speed) {
    final strength = _classifyImpact(speed);
    if (strength == _ImpactStrength.none) return;
    final now = DateTime.now();
    if (_lastHapticAt != null &&
        now.difference(_lastHapticAt!) < _hapticCooldown) {
      return;
    }
    _lastHapticAt = now;
    switch (strength) {
      case _ImpactStrength.light:
        HapticFeedback.lightImpact();
      case _ImpactStrength.medium:
        HapticFeedback.mediumImpact();
      case _ImpactStrength.none:
        break;
    }
  }

  // ---- Gestures (raw Listener -- no gesture-arena latency) -------------

  void _onPointerDown(PointerDownEvent event, HeroAbacusGeometry geometry) {
    if (_activePointer != null) return;
    _controller.updateGeometry(geometry);
    final hit = _controller.hitTest(event.localPosition);
    if (hit == null) return;
    _activePointer = event.pointer;
    _controller.beginDrag(hit.$1, hit.$2, event.timeStamp);
    _startTicking();
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer) return;
    _controller.updateDrag(event.localPosition.dx, event.timeStamp);
  }

  void _onPointerUp(PointerEvent event) {
    if (event.pointer != _activePointer) return;
    _activePointer = null;
    _controller.endDrag();
    _startTicking();
  }

  // ---- Teaser (currently disabled; kept correctly wired for restoral) --

  void _playTeaser() {
    if (!mounted) return;
    const scenarios = HeroAbacusScenarios.all;
    final index = widget.scenarioIndex.clamp(0, scenarios.length - 1);
    final scenario = scenarios[index];
    _runTeaserMove(
      scenario.first,
      onComplete: () {
        if (!mounted) return;
        _runTeaserMove(
          scenario.second,
          onComplete: () {
            if (mounted) widget.onIntroAnimationComplete?.call();
          },
        );
      },
    );
  }

  void _runTeaserMove(
    HeroAbacusTeaserMove move, {
    required VoidCallback onComplete,
  }) {
    final animController = AnimationController(
      vsync: this,
      duration: move.duration,
    );
    _teaserControllers.add(animController);
    final curved = CurvedAnimation(
      parent: animController,
      curve: Curves.easeInOutSine,
    );
    final tween = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: move.offsetFraction),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween(begin: move.offsetFraction, end: 0.0),
        weight: 50,
      ),
    ]);
    final animation = tween.animate(curved);
    final baseFraction = _controller.positions[move.row][move.column];

    void listener() {
      _controller.setBeadPositionDirect(
        move.row,
        move.column,
        baseFraction + animation.value,
      );
    }

    animation.addListener(listener);
    animController.forward().whenComplete(() {
      animation.removeListener(listener);
      _teaserControllers.remove(animController);
      animController.dispose();
      onComplete();
    });
  }

  // ---- Build -------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final geometry = HeroAbacusGeometry.forWidth(widget.width);
    _controller.updateGeometry(geometry);

    Widget child = CustomPaint(
      size: Size(geometry.width, geometry.height),
      painter: HeroAbacusPainter(geometry: geometry, controller: _controller),
    );

    if (widget.interactive) {
      child = Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) => _onPointerDown(event, geometry),
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerUp,
        child: child,
      );
    }

    return RepaintBoundary(
      child: SizedBox(
        width: geometry.width,
        height: geometry.height,
        child: child,
      ),
    );
  }
}
