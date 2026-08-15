import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/images/product_image.dart';

/// A single, compact, photo-forward ingredient tile — sized for the v2
/// horizontal ingredient carousel (`bowl_builder_screen.dart`'s ingredient
/// section), where [width] cards fit ~2.2–2.6 to a phone-width viewport and
/// simply more of them at once on a wider one, with no separate breakpoint
/// layout needed. Deliberately its own widget, not a variant of
/// `OptionSelectionCard` (Product Detail's shared modifier row) — that
/// widget stays exactly as Faz 7 shipped it; this one is owned entirely by
/// Bowl Builder and free to look completely different.
///
/// Two interaction modes, matching the category's own rule:
/// - Toggle ([allowsQuantity] false, 7 of 9 categories): the whole card is
///   tappable via [onTap] — one portion, tap again to remove. The trailing
///   control is a label only ("Ekle" / "✓ Eklendi"), not a second tap
///   target.
/// - Quantity ([allowsQuantity] true, Proteinler/Karbonhidratlar only): the
///   card itself isn't a single tap target. Before selection it shows a
///   tappable "Ekle" pill (calls [onIncrement]); once [quantity] > 0 that
///   pill is replaced by an always-visible −/adet/+ stepper.
///
/// [caloriesKcal]/[proteinGrams] show a one-line nutrition summary under the
/// price — the compact card intentionally omits fat/carbs (those live in
/// the screen-level `BowlBuilderLiveMetrics` dashboard) to stay legible at
/// this width.
///
/// Both modes share the same selected-state visuals (border, tint, shadow,
/// checkmark) and the same brief "pulse" whenever [quantity] increases —
/// the tactile confirmation that a tap actually did something. Per the v2
/// brief's own guidance, this pulse plus `BowlCanvas`'s existing layer
/// fade/scale-in animation are the entire "ingredient added to my bowl"
/// feedback loop — a literal flight/transition from this card to the canvas
/// was considered and deliberately not built (would need shared
/// `GlobalKey`/coordinate plumbing across two independent widget subtrees
/// for a cosmetic effect); see the final report for that call.
class IngredientCard extends StatefulWidget {
  final String name;
  final double price;
  final String? imageKey;
  final int quantity;
  final bool allowsQuantity;
  final double caloriesKcal;
  final double proteinGrams;
  final VoidCallback? onTap;
  final VoidCallback? onIncrement;
  final VoidCallback? onDecrement;

  static const double width = 168;

  const IngredientCard({
    super.key,
    required this.name,
    required this.price,
    required this.imageKey,
    required this.quantity,
    required this.allowsQuantity,
    required this.caloriesKcal,
    required this.proteinGrams,
    this.onTap,
    this.onIncrement,
    this.onDecrement,
  }) : assert(
          allowsQuantity
              ? (onIncrement != null && onDecrement != null)
              : onTap != null,
          'Quantity cards need onIncrement/onDecrement; toggle cards need onTap.',
        );

  @override
  State<IngredientCard> createState() => _IngredientCardState();
}

class _IngredientCardState extends State<IngredientCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseScale;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _pulseScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.05)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 1,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.05, end: 1.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 1,
      ),
    ]).animate(_pulseController);
  }

  @override
  void didUpdateWidget(covariant IngredientCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Every added unit gets its own little confirmation — a fresh toggle-on
    // and a 3rd Izgara Tavuk both deserve to feel like something happened.
    if (widget.quantity > oldWidget.quantity) {
      _pulseController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSelected = widget.quantity > 0;

    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.kLarge,
        border: Border.all(
          color: isSelected ? AppColors.primary : AppColors.border,
          width: isSelected ? 2 : 1,
        ),
        boxShadow: isSelected ? AppShadows.floating : AppShadows.card,
      ),
      child: ClipRRect(
        borderRadius: AppRadius.kLarge,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The card's own top-level Semantics label (below) already
            // says everything a screen reader needs — the image and this
            // name/price text would otherwise also expose themselves as
            // separate, redundant semantics, so they're excluded here.
            // The stepper (quantity mode) is deliberately NOT excluded:
            // its +/- buttons must stay individually reachable.
            ExcludeSemantics(
              child: AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ProductImage(
                      imageKey: widget.imageKey ?? '',
                      borderRadius: BorderRadius.zero,
                      placeholderIconSize: 36,
                    ),
                    Positioned(
                      top: AppSpacing.sm,
                      right: AppSpacing.sm,
                      child: AnimatedScale(
                        scale: isSelected ? 1.0 : 0.6,
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutBack,
                        child: AnimatedOpacity(
                          opacity: isSelected ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 150),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                              boxShadow: AppShadows.subtle,
                            ),
                            child: const Icon(
                              Icons.check_rounded,
                              color: AppColors.onPrimary,
                              size: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ExcludeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.name,
                          style: AppTypography.bodyLarge.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '+${widget.price.toStringAsFixed(0)} TL',
                          style: AppTypography.bodyMedium.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${widget.caloriesKcal.toStringAsFixed(0)} kcal · '
                          '${widget.proteinGrams.toStringAsFixed(0)} g protein',
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  if (widget.allowsQuantity)
                    isSelected
                        ? _QuantityStepper(
                            quantity: widget.quantity,
                            onIncrement: widget.onIncrement!,
                            onDecrement: widget.onDecrement!,
                          )
                        : _EklePill(onTap: widget.onIncrement!)
                  else
                    // Purely decorative in this mode — the parent
                    // Semantics' explicit `label` above already fully
                    // describes selected state; without this, the pill's
                    // own "Ekle"/"✓ Eklendi" text would merge into (and
                    // corrupt) that label.
                    ExcludeSemantics(
                      child: _StatusPill(isSelected: isSelected),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    final animatedCard = AnimatedBuilder(
      animation: _pulseScale,
      builder: (context, child) {
        return Transform.scale(scale: _pulseScale.value, child: child);
      },
      child: card,
    );

    final sized = SizedBox(width: IngredientCard.width, child: animatedCard);

    if (widget.allowsQuantity) {
      return Semantics(
        container: true,
        explicitChildNodes: true,
        label: '${widget.name}, +${widget.price.toStringAsFixed(0)} TL, '
            '${widget.quantity} adet seçili',
        child: sized,
      );
    }

    return Semantics(
      container: true,
      button: true,
      selected: isSelected,
      label: '${widget.name}, +${widget.price.toStringAsFixed(0)} TL'
          '${isSelected ? ', seçili' : ''}',
      child: Material(
        color: Colors.transparent,
        borderRadius: AppRadius.kLarge,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: AppRadius.kLarge,
          child: sized,
        ),
      ),
    );
  }
}

/// Toggle-mode's trailing affordance — a label only, not its own tap
/// target, since the whole card already handles the tap in that mode.
class _StatusPill extends StatelessWidget {
  final bool isSelected;

  const _StatusPill({required this.isSelected});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isSelected ? AppColors.primary : Colors.transparent,
        border: isSelected ? null : Border.all(color: AppColors.border),
        borderRadius: AppRadius.kPill,
      ),
      child: Text(
        isSelected ? '✓ Eklendi' : 'Ekle',
        style: AppTypography.labelLarge.copyWith(
          fontWeight: FontWeight.bold,
          color: isSelected ? AppColors.onPrimary : AppColors.textPrimary,
        ),
      ),
    );
  }
}

/// Quantity-mode's initial (quantity == 0) affordance — independently
/// tappable, since the card itself carries no [IngredientCard.onTap] in
/// this mode.
class _EklePill extends StatelessWidget {
  final VoidCallback onTap;

  const _EklePill({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: AppRadius.kPill,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.kPill,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: AppRadius.kPill,
          ),
          child: Text(
            'Ekle',
            style: AppTypography.labelLarge.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _QuantityStepper extends StatelessWidget {
  final int quantity;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  const _QuantityStepper({
    required this.quantity,
    required this.onIncrement,
    required this.onDecrement,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _StepperButton(
          icon: Icons.remove_rounded,
          onPressed: quantity > 0 ? onDecrement : null,
          isPrimary: false,
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          transitionBuilder: (child, animation) => ScaleTransition(
            scale: animation,
            child: FadeTransition(opacity: animation, child: child),
          ),
          child: Text(
            '$quantity',
            key: ValueKey(quantity),
            style: AppTypography.titleMedium,
          ),
        ),
        _StepperButton(
          icon: Icons.add_rounded,
          onPressed: onIncrement,
          isPrimary: true,
        ),
      ],
    );
  }
}

class _StepperButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final bool isPrimary;

  const _StepperButton({
    required this.icon,
    required this.onPressed,
    required this.isPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isPrimary ? AppColors.primary : AppColors.surfaceVariant,
      shape: const CircleBorder(),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        padding: EdgeInsets.zero,
        color: isPrimary ? AppColors.onPrimary : AppColors.textPrimary,
        disabledColor: AppColors.textDisabled,
      ),
    );
  }
}
