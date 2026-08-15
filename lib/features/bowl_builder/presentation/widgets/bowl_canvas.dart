import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/models/bowl_builder_ingredient.dart';
import '../../domain/models/bowl_builder_state.dart';
import '../../domain/models/bowl_layer_type.dart';
import '../../domain/services/bowl_layer_image_resolver.dart';
import '../providers/bowl_builder_provider.dart';

/// Renders the bowl as a stack of transparent PNG layers — the visual
/// counterpart to the picker's selections, built ahead of the official
/// Abaküs Ingredient Asset Library (Faz 8.2, extended Faz 8.3 2026-07-24).
/// `bowl_empty.png` is drawn exactly once, underneath everything; every
/// selected ingredient then draws its own overlay on top, grouped into
/// [BowlLayerType]'s six layers and stacked in that enum's declared order
/// (base → protein → vegetable → cheese → sauce → topping) — always that
/// order, regardless of the order ingredients were actually picked in.
///
/// A pure compositor: it has no opinion on size or shape (no `AspectRatio`,
/// no clipping, no background) — every caller wraps it in whatever box its
/// context needs (a large square for the picker's live preview and the
/// Summary step, a small square for a Cart line's thumbnail). This is what
/// makes one implementation genuinely reusable at three very different
/// sizes instead of three copies of the same compositing logic.
///
/// Two data sources, picked automatically:
/// - [ingredients] omitted (`null`, the default) — reads the live,
///   in-progress selection from [bowlBuilderProvider] itself, used by the
///   picker's live preview and the Summary step.
/// - [ingredients] provided explicitly — renders exactly that list and
///   never touches [bowlBuilderProvider]. Used for a Cart line, whose bowl
///   only exists as a frozen `List<SelectedModifier>` — the caller resolves
///   each modifier's `optionId` back through the catalog and passes the
///   result in here.
///
/// A quantity-N ingredient (Proteinler/Karbonhidratlar can be added more
/// than once) still draws its overlay exactly once — this is a visual, not
/// a per-unit render; how many times an ingredient was added only affects
/// price, never how many copies of its layer appear on the bowl.
class BowlCanvas extends ConsumerStatefulWidget {
  final List<BowlBuilderIngredient>? ingredients;

  const BowlCanvas({super.key, this.ingredients});

  @override
  ConsumerState<BowlCanvas> createState() => _BowlCanvasState();
}

class _BowlCanvasState extends ConsumerState<BowlCanvas>
    with SingleTickerProviderStateMixin {
  // Bowl Canvas Visual Asset Fix (2026-08-08): a subtle whole-bowl scale
  // pulse, layered on top of (never replacing) each ingredient's own
  // fade/scale-in animation in `_BowlLayerStack` below — the two run
  // independently and both stay small/restrained on purpose ("no bounce,
  // no game effect"). Only fires in live mode ([ingredients] omitted):
  // a frozen, externally-provided list (e.g. a Cart line) has no "just
  // added" moment to react to.
  static const _pulseDuration = Duration(milliseconds: 190);
  static const _pulseMaxScale = 1.015;

  late final AnimationController _pulseController;
  late final Animation<double> _pulseScale;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: _pulseDuration,
    );
    _pulseScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: _pulseMaxScale)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 1,
      ),
      TweenSequenceItem(
        tween: Tween(begin: _pulseMaxScale, end: 1.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 1,
      ),
    ]).animate(_pulseController);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  int _totalSelectedUnits(BowlBuilderState state) =>
      state.selectedQuantitiesByIngredient.values.fold(0, (a, b) => a + b);

  @override
  Widget build(BuildContext context) {
    if (widget.ingredients == null) {
      ref.listen<BowlBuilderState>(bowlBuilderProvider, (previous, next) {
        if (previous == null) return;
        if (_totalSelectedUnits(next) > _totalSelectedUnits(previous)) {
          _pulseController.forward(from: 0);
        }
      });
    }

    final resolved = widget.ingredients ?? _liveSelection(ref);
    final byLayer = _groupByLayer(resolved);

    return ScaleTransition(
      scale: _pulseScale,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const _BowlBaseImage(),
          for (final layer in BowlLayerType.values)
            RepaintBoundary(
              child: _BowlLayerStack(
                key: ValueKey(layer),
                ingredients: byLayer[layer]!,
              ),
            ),
        ],
      ),
    );
  }

  List<BowlBuilderIngredient> _liveSelection(WidgetRef ref) {
    final state = ref.watch(bowlBuilderProvider);
    final catalog = ref.watch(bowlBuilderCatalogRepositoryProvider);
    final result = <BowlBuilderIngredient>[];
    state.selectedQuantitiesByIngredient.forEach((ingredientId, quantity) {
      if (quantity <= 0) return;
      final ingredient = catalog.ingredientById(ingredientId);
      if (ingredient != null) result.add(ingredient);
    });
    return result;
  }
}

Map<BowlLayerType, List<BowlBuilderIngredient>> _groupByLayer(
  List<BowlBuilderIngredient> ingredients,
) {
  final byLayer = <BowlLayerType, List<BowlBuilderIngredient>>{
    for (final layer in BowlLayerType.values) layer: <BowlBuilderIngredient>[],
  };
  for (final ingredient in ingredients) {
    byLayer[BowlLayerType.forCategoryId(ingredient.categoryId)]!
        .add(ingredient);
  }
  for (final list in byLayer.values) {
    list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }
  return byLayer;
}

/// The bowl itself — rendered exactly once, never duplicated. Falls back to
/// a neutral placeholder (never a broken-image icon) until `bowl_empty.png`
/// exists.
class _BowlBaseImage extends StatelessWidget {
  const _BowlBaseImage();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      BowlLayerImageResolver.bowlBasePath(),
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) =>
          const _BowlBasePlaceholder(),
    );
  }
}

/// Neutral stand-in for the real `bowl_empty.png` — a plain generic-food
/// icon (`Icons.ramen_dining_rounded`, the prior placeholder) reads as "no
/// image", not as *this app's* empty bowl. This paints a simple, unbranded
/// bowl silhouette instead, so the customer still recognizes "this is my
/// bowl" before the real asset lands. Explicitly a temporary placeholder,
/// not the final premium asset — see this feature's asset report.
class _BowlBasePlaceholder extends StatelessWidget {
  const _BowlBasePlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: CustomPaint(
        size: Size.infinite,
        painter: _BowlSilhouettePainter(),
      ),
    );
  }
}

class _BowlSilhouettePainter extends CustomPainter {
  const _BowlSilhouettePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;
    final rimWidth = width * 0.72;
    final rimHeight = height * 0.11;
    final rimCenter = Offset(width / 2, height * 0.4);
    final bodyBottomHalfWidth = rimWidth * 0.32;
    final bodyBottomY = rimCenter.dy + height * 0.34;

    final bodyPath = Path()
      ..moveTo(rimCenter.dx - rimWidth / 2, rimCenter.dy)
      ..quadraticBezierTo(
        rimCenter.dx - rimWidth / 2,
        bodyBottomY,
        rimCenter.dx - bodyBottomHalfWidth,
        bodyBottomY,
      )
      ..lineTo(rimCenter.dx + bodyBottomHalfWidth, bodyBottomY)
      ..quadraticBezierTo(
        rimCenter.dx + rimWidth / 2,
        bodyBottomY,
        rimCenter.dx + rimWidth / 2,
        rimCenter.dy,
      )
      ..close();

    canvas.drawPath(
      bodyPath,
      Paint()
        ..color = AppColors.surfaceVariant
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      bodyPath,
      Paint()
        ..color = AppColors.primary.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    final rimRect = Rect.fromCenter(
      center: rimCenter,
      width: rimWidth,
      height: rimHeight,
    );
    canvas.drawOval(
      rimRect,
      Paint()
        ..color = AppColors.background
        ..style = PaintingStyle.fill,
    );
    canvas.drawOval(
      rimRect,
      Paint()
        ..color = AppColors.primary.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(covariant _BowlSilhouettePainter oldDelegate) => false;
}

/// One [BowlLayerType]'s worth of overlays. Owns each currently-shown
/// ingredient's own enter/exit animation (Faz 8.3, 2026-07-24) — a plain
/// `Stack` rebuild would just discard and recreate widgets on every
/// selection change with no transition; this keeps a removed ingredient
/// mounted just long enough to fade+scale out before actually dropping it.
///
/// - A genuinely new id fades/scales in (0.92 → 1.00 opacity+scale,
///   220ms, ease out).
/// - A removed id fades/scales out (1.00 → 0.92, 175ms) and is
///   only removed from the tree once that finishes.
/// - The very first build (whatever is already selected when this widget
///   first mounts) shows instantly, no animation — this is what makes a
///   Cart thumbnail (a frozen, already-decided bowl) render steady-state
///   with zero animation, with no special-casing needed anywhere else.
/// - A quantity change on an already-selected ingredient never touches its
///   controller — this only reacts to an id appearing/disappearing.
class _BowlLayerStack extends StatefulWidget {
  final List<BowlBuilderIngredient> ingredients;

  const _BowlLayerStack({super.key, required this.ingredients});

  @override
  State<_BowlLayerStack> createState() => _BowlLayerStackState();
}

class _BowlLayerStackState extends State<_BowlLayerStack>
    with TickerProviderStateMixin {
  static const _enterDuration = Duration(milliseconds: 220);
  static const _exitDuration = Duration(milliseconds: 175);

  final Map<String, BowlBuilderIngredient> _tracked = {};
  final Map<String, AnimationController> _controllers = {};

  @override
  void initState() {
    super.initState();
    _sync(widget.ingredients, animate: false);
  }

  @override
  void didUpdateWidget(covariant _BowlLayerStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync(widget.ingredients, animate: true);
  }

  void _sync(List<BowlBuilderIngredient> next, {required bool animate}) {
    final nextIds = {for (final ingredient in next) ingredient.id: ingredient};

    for (final entry in nextIds.entries) {
      final id = entry.key;
      final existing = _controllers[id];
      if (existing == null) {
        _tracked[id] = entry.value;
        final controller = AnimationController(
          vsync: this,
          duration: _enterDuration,
          reverseDuration: _exitDuration,
        );
        _controllers[id] = controller;
        if (animate) {
          controller.forward();
        } else {
          controller.value = 1;
        }
        continue;
      }
      // Re-selected while its exit animation was still playing (or had
      // just finished but wasn't pruned yet) — resume forward from
      // wherever it currently is instead of waiting for a full cycle.
      if (existing.status == AnimationStatus.reverse ||
          existing.status == AnimationStatus.dismissed) {
        _tracked[id] = entry.value;
        existing.forward();
      }
    }

    for (final id in _tracked.keys.toList()) {
      if (nextIds.containsKey(id)) continue;
      final controller = _controllers[id];
      if (controller == null) continue;
      if (controller.status == AnimationStatus.reverse ||
          controller.status == AnimationStatus.dismissed) {
        continue;
      }
      controller.reverse().whenCompleteOrCancel(() {
        if (!mounted) return;
        // Interrupted by a forward() (re-selection) before it finished
        // reversing — don't prune something that's coming back.
        if (controller.status != AnimationStatus.dismissed) return;
        setState(() => _tracked.remove(id));
        _controllers.remove(id);
        controller.dispose();
      });
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_tracked.isEmpty) return const SizedBox.shrink();
    final sorted = _tracked.values.toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    return Stack(
      fit: StackFit.expand,
      children: [
        for (final ingredient in sorted)
          if (ingredient.imageKey != null)
            _BowlLayerOverlay(
              key: ValueKey(ingredient.id),
              controller: _controllers[ingredient.id]!,
              assetPath: BowlLayerImageResolver.layerPath(ingredient.imageKey!),
            ),
      ],
    );
  }
}

/// One ingredient's overlay, faded/scaled by [controller] — an ingredient
/// with no bundled PNG yet renders nothing, never a broken-image icon.
class _BowlLayerOverlay extends StatelessWidget {
  final AnimationController controller;
  final String assetPath;

  const _BowlLayerOverlay({
    super.key,
    required this.controller,
    required this.assetPath,
  });

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: controller,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
        child: Image.asset(
          assetPath,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
        ),
      ),
    );
  }
}
