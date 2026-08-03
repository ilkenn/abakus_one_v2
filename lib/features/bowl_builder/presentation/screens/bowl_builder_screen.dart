import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/layout/app_breakpoints.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/layout/app_section_header.dart';
import '../../../cart/presentation/providers/cart_provider.dart';
import '../../data/bowl_builder_catalog.dart';
import '../../domain/models/bowl_builder_category.dart';
import '../../domain/models/bowl_builder_step.dart';
import '../providers/bowl_builder_provider.dart';
import '../providers/bowl_builder_recipe_provider.dart';
import '../widgets/bowl_canvas.dart';
import '../widgets/builder_progress.dart';
import '../widgets/builder_summary.dart';
import '../widgets/ingredient_card.dart';

class BowlBuilderScreen extends ConsumerStatefulWidget {
  const BowlBuilderScreen({super.key});

  @override
  ConsumerState<BowlBuilderScreen> createState() => _BowlBuilderScreenState();
}

class _BowlBuilderScreenState extends ConsumerState<BowlBuilderScreen> {
  late final TextEditingController _noteController;

  @override
  void initState() {
    super.initState();
    _noteController =
        TextEditingController(text: ref.read(bowlBuilderProvider).note);
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _addToCart(BuildContext context, WidgetRef ref) {
    final selectedModifiers = ref.read(bowlBuilderSelectedModifiersProvider);
    final state = ref.read(bowlBuilderProvider);
    final unitPrice = ref.read(bowlBuilderTotalPriceProvider);
    final id = 'custom_bowl_${DateTime.now().millisecondsSinceEpoch}';

    ref.read(cartProvider.notifier).addToCart(
          id: id,
          name: 'Kendi Bowlun',
          desc: selectedModifiers.map((m) => m.optionName).join(', '),
          // Bowl Builder has no starting price (product decision,
          // 2026-07-23) — the entire cost is carried by selectedModifiers,
          // so the item's own base price is 0.
          price: 0,
          quantity: state.quantity,
          selectedModifiers: selectedModifiers,
          note: state.note.trim(),
        );

    // Records an immutable Phase 7H recipe snapshot for this bowl at
    // the moment it's finalized into the cart — the closest analog
    // this app's customer-facing flow has to "order submission" (see
    // `CreateBowlBuilderRecipeSnapshot`'s doc comment). Best-effort:
    // never blocks or fails cart-add itself, since Bowl Builder must
    // stay fully usable even with no `BowlBuilderIngredientRecipeMapping`
    // configured yet.
    unawaited(
      ref.read(createBowlBuilderRecipeSnapshotProvider).call(
            contextId: id,
            organizationId: 'org-1',
            branchId: 'branch-1',
            selections: state.selectedQuantitiesByIngredient,
            priceBasisMinorUnits: (unitPrice * 100).round(),
            priceBasisCurrencyCode: 'TRY',
            performedAt: DateTime.now(),
          ),
    );

    ref.read(bowlBuilderProvider.notifier).reset();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Bowlun sepete eklendi!'),
        duration: Duration(seconds: 2),
      ),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(bowlBuilderProvider);
    final catalog = ref.watch(bowlBuilderCatalogRepositoryProvider);
    final grandTotal = ref.watch(bowlBuilderGrandTotalProvider);
    final selectedModifiers = ref.watch(bowlBuilderSelectedModifiersProvider);

    const steps = BowlBuilderStep.values;
    final stepIndex = steps.indexOf(state.currentStep);
    final isSummaryStep = state.currentStep == BowlBuilderStep.summary;
    final isFirstStep = stepIndex == 0;
    final currentCategory =
        isSummaryStep ? null : _categoryById(catalog, state.currentStep.name);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kendi Bowlunu Yarat'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xl,
                vertical: AppSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isSummaryStep
                        ? 'Özet'
                        : 'Adım ${stepIndex + 1}/${steps.length - 1} · ${currentCategory?.name ?? ''}',
                    style: AppTypography.labelLarge.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  BuilderProgress(
                    currentIndex: stepIndex,
                    totalSteps: steps.length,
                  ),
                ],
              ),
            ),
            // Live preview while picking — hidden on the summary step,
            // which already shows the same BowlCanvas at full size below.
            // Sits outside the AnimatedSwitcher'd step content on purpose:
            // it must stay mounted across step navigation so its per-layer
            // enter/exit animations only ever fire on an actual ingredient
            // change, never on switching steps.
            if (!isSummaryStep)
              const Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  0,
                  AppSpacing.xl,
                  AppSpacing.md,
                ),
                child: SizedBox(
                  height: 120,
                  child: ClipRRect(
                    borderRadius: AppRadius.kMedium,
                    child: ColoredBox(
                      color: AppColors.surfaceVariant,
                      child: BowlCanvas(),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.04, 0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: KeyedSubtree(
                  key: ValueKey(state.currentStep),
                  child: isSummaryStep
                      ? SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xl,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const AspectRatio(
                                aspectRatio: 1,
                                child: ClipRRect(
                                  borderRadius: AppRadius.kLarge,
                                  child: ColoredBox(
                                    color: AppColors.surfaceVariant,
                                    child: BowlCanvas(),
                                  ),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              BuilderSummary(
                                selectedModifiers: selectedModifiers,
                                grandTotal: grandTotal,
                                quantity: state.quantity,
                                onIncrement: () => ref
                                    .read(bowlBuilderProvider.notifier)
                                    .incrementQuantity(),
                                onDecrement: () => ref
                                    .read(bowlBuilderProvider.notifier)
                                    .decrementQuantity(),
                                noteController: _noteController,
                                onNoteChanged: (value) => ref
                                    .read(bowlBuilderProvider.notifier)
                                    .setNote(value),
                              ),
                            ],
                          ),
                        )
                      : _CategoryStepBody(category: currentCategory!),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isSummaryStep) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        'Toplam (şu ana kadar)',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (child, animation) => ScaleTransition(
                        scale: animation,
                        child: FadeTransition(opacity: animation, child: child),
                      ),
                      child: Text(
                        '${grandTotal.toStringAsFixed(0)} TL',
                        key: ValueKey(grandTotal),
                        style: AppTypography.priceMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              Row(
                children: [
                  if (!isFirstStep) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => ref
                            .read(bowlBuilderProvider.notifier)
                            .previousStep(),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.md,
                          ),
                        ),
                        child: const Text('Geri'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                  ],
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: isSummaryStep
                          ? () => _addToCart(context, ref)
                          : () =>
                              ref.read(bowlBuilderProvider.notifier).nextStep(),
                      style: ElevatedButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(vertical: AppSpacing.md),
                      ),
                      child: Text(
                        isSummaryStep
                            ? 'Sepete Ekle · ${grandTotal.toStringAsFixed(0)} TL'
                            : 'Devam Et',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One category step's body — a responsive grid of [IngredientCard]s.
/// Phones stay single-column on purpose (large food photography sells the
/// experience harder than a thumbnail); tablets and wider get more columns
/// since there's room without shrinking photos down (see [AppBreakpoints]).
///
/// No category is required and none has a cap, so this is purely a
/// rendering choice: Proteinler/Karbonhidratlar cards show an always-visible
/// +/- stepper (the same ingredient can be added any number of times);
/// every other category's cards are a single tap-to-toggle (one portion,
/// tap again to remove, unlimited distinct ingredients).
class _CategoryStepBody extends ConsumerWidget {
  final BowlBuilderCategory category;

  const _CategoryStepBody({required this.category});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(bowlBuilderCatalogRepositoryProvider);
    final state = ref.watch(bowlBuilderProvider);
    final notifier = ref.read(bowlBuilderProvider.notifier);
    final ingredients = catalog.ingredientsFor(category.id);

    return LayoutBuilder(
      builder: (context, constraints) {
        final gridDelegate = _gridDelegateFor(
          constraints.maxWidth - AppSpacing.xl * 2,
          hasStepper: category.allowsQuantity,
        );

        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              sliver: SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: AppSectionHeader(
                    title: category.name,
                    subtitle: category.allowsQuantity
                        ? 'İstediğin kadar ekleyebilirsin — her biri kendi fiyatını ekler.'
                        : 'İstediğin kadar malzeme seçebilirsin, her biri kendi fiyatını ekler.',
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              sliver: SliverGrid(
                gridDelegate: gridDelegate,
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final ingredient = ingredients[index];
                    return RepaintBoundary(
                      child: category.allowsQuantity
                          ? IngredientCard(
                              name: ingredient.name,
                              price: ingredient.price,
                              imageKey: ingredient.imageKey,
                              quantity: state.quantityFor(ingredient.id),
                              allowsQuantity: true,
                              onIncrement: () =>
                                  notifier.incrementIngredient(ingredient.id),
                              onDecrement: () =>
                                  notifier.decrementIngredient(ingredient.id),
                            )
                          : IngredientCard(
                              name: ingredient.name,
                              price: ingredient.price,
                              imageKey: ingredient.imageKey,
                              quantity: state.quantityFor(ingredient.id),
                              allowsQuantity: false,
                              onTap: () =>
                                  notifier.toggleIngredient(ingredient.id),
                            ),
                    );
                  },
                  childCount: ingredients.length,
                ),
              ),
            ),
            const SliverPadding(
              padding: EdgeInsets.only(bottom: AppSpacing.xl),
            ),
          ],
        );
      },
    );
  }
}

/// A grid delegate sized so each card's image reads as roughly square
/// regardless of column count — [availableWidth] is the space the grid
/// itself has (already excluding the screen's own horizontal padding).
SliverGridDelegateWithFixedCrossAxisCount _gridDelegateFor(
  double availableWidth, {
  required bool hasStepper,
}) {
  final columns = AppBreakpoints.columnsForWidth(availableWidth);
  const spacing = AppSpacing.md;
  final totalSpacing = spacing * (columns - 1);
  final cardWidth = (availableWidth - totalSpacing) / columns;
  // Approximate fixed height of the text block below the square image
  // (name up to 2 lines + price, plus the stepper row when present) —
  // tuned so cards don't overflow at default text scale; independent of
  // column count since it doesn't grow with card width.
  final textBlockHeight = hasStepper ? 128.0 : 88.0;
  final cardHeight = cardWidth + textBlockHeight;

  return SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: columns,
    crossAxisSpacing: spacing,
    mainAxisSpacing: spacing,
    childAspectRatio: cardWidth / cardHeight,
  );
}

/// The category whose id matches [categoryId], or `null` if the catalog
/// doesn't have one — a defensive lookup, not expected to ever miss since
/// `BowlBuilderStep`'s values are defined to match the catalog's category
/// ids exactly.
BowlBuilderCategory? _categoryById(
  BowlBuilderCatalogRepository catalog,
  String categoryId,
) {
  for (final category in catalog.categories) {
    if (category.id == categoryId) return category;
  }
  return null;
}
