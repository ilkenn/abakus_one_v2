import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/models/currency.dart';
import '../../../../shared/models/money.dart';
import '../../../cart/presentation/providers/cart_provider.dart';
import '../../../cart/presentation/providers/shopping_channel_provider.dart';
import '../../../menu/domain/pricing/channel_price_resolver.dart';
import '../../../menu/domain/pricing/channel_pricing_policy.dart';
import '../../../menu/presentation/providers/channel_price_display_provider.dart';
import '../../data/bowl_builder_catalog.dart';
import '../../domain/models/bowl_builder_category.dart';
import '../../domain/models/bowl_builder_step.dart';
import '../providers/bowl_builder_provider.dart';
import '../providers/bowl_builder_recipe_provider.dart';
import '../widgets/bowl_builder_action_bar.dart';
import '../widgets/bowl_builder_category_selector.dart';
import '../widgets/bowl_builder_live_metrics.dart';
import '../widgets/bowl_canvas.dart';
import '../widgets/build_your_bowl_hero.dart';
import '../widgets/builder_summary.dart';
import '../widgets/ingredient_card.dart';

/// Bowl Builder v2 — category-driven redesign (2026-08-08). Replaces the
/// old linear "Adım N/9" wizard (`BuilderProgress`, forced Geri/Devam Et)
/// with free-roaming navigation: a horizontal category selector the
/// customer can jump around in at any time, a hero + price/nutrition
/// dashboard, and a persistent bottom action bar. The underlying state
/// machine — `BowlBuilderStep`, `bowlBuilderProvider`'s selection/quantity/
/// pricing rules, cart and recipe-snapshot wiring — is unchanged; this
/// screen only reinterprets `state.currentStep` as "which category is
/// active" instead of "which step of a linear form".
///
/// The main editing screen's hero is [BuildYourBowlHero] — a static
/// approved banner (Bowl Builder Static Hero task, 2026-08-08), not a live
/// `BowlCanvas` preview. `BowlCanvas` itself is untouched and still drives
/// the live preview on the Summary step below.
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

    // Gel Al (Faz C): the channel adjustment (+20 TL default) applies
    // exactly once per bowl unit, never per ingredient — computed here as
    // a standalone amount (ingredientTotal fed in as zero) and added to
    // the item's own base `price`, since `selectedModifiers` already
    // carries the full ingredient sum and `CartItem.unitPrice` would
    // otherwise double-count it. Resolves to 0 for every non-takeaway
    // channel (today's dine-in/delivery), so the "no starting price"
    // product decision (2026-07-23) is unchanged outside Gel Al.
    final channelContext = ref.read(shoppingChannelProvider);
    final policy = ref.read(channelPricingPolicySnapshotProvider).valueOrNull ??
        const ChannelPricingPolicy();
    final channelAdjustment = ChannelPriceResolver.resolveBowlUnitPrice(
      ingredientTotal: Money.zero(Currency.tryLira),
      channel: channelContext.channel,
      policy: policy,
    );
    final channelAdjustmentDouble = channelAdjustment.minorUnits /
        channelAdjustment.currency.minorUnitsPerWhole;

    ref.read(cartProvider.notifier).addToCart(
          id: id,
          name: 'Kendi Bowlun',
          desc: selectedModifiers.map((m) => m.optionName).join(', '),
          price: channelAdjustmentDouble,
          quantity: state.quantity,
          selectedModifiers: selectedModifiers,
          note: state.note.trim(),
          pricedForChannel: channelContext.channel,
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

  Future<void> _handleReset(BuildContext context, WidgetRef ref) async {
    final state = ref.read(bowlBuilderProvider);
    if (state.selectedQuantitiesByIngredient.isEmpty) {
      ref.read(bowlBuilderProvider.notifier).reset();
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bowlu Sıfırla'),
        content: const Text(
          'Seçtiğin tüm malzemeler kaldırılacak. Emin misin?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sıfırla'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    ref.read(bowlBuilderProvider.notifier).reset();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(bowlBuilderProvider);
    final catalog = ref.watch(bowlBuilderCatalogRepositoryProvider);
    final grandTotal = ref.watch(bowlBuilderGrandTotalProvider);
    final totalCalories = ref.watch(bowlBuilderTotalCaloriesProvider);
    final totalProtein = ref.watch(bowlBuilderTotalProteinProvider);
    final selectedModifiers = ref.watch(bowlBuilderSelectedModifiersProvider);

    final isSummaryStep = state.currentStep == BowlBuilderStep.summary;
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
        actions: [
          TextButton(
            onPressed: () => _handleReset(context, ref),
            child: const Text('Sıfırla'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Always visible, always jumpable — no forced linear
            // progression through categories.
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xl,
                vertical: AppSpacing.md,
              ),
              child: BowlBuilderCategorySelector(
                categories: catalog.categories,
                currentStep: state.currentStep,
                onCategorySelected: (step) =>
                    ref.read(bowlBuilderProvider.notifier).goToStep(step),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Static editorial hero + live dashboard — hidden on
                    // the summary step, which still shows its own live
                    // BowlCanvas + BowlBuilderLiveMetrics below (Bowl
                    // Builder Static Hero task, 2026-08-08: only the main
                    // editing screen's hero swapped from a live preview to
                    // the approved static banner; Summary is unchanged).
                    if (!isSummaryStep) ...[
                      const Padding(
                        padding: EdgeInsets.fromLTRB(
                          AppSpacing.xl,
                          0,
                          AppSpacing.xl,
                          AppSpacing.md,
                        ),
                        child: BuildYourBowlHero(),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: AppSpacing.xl,
                        ),
                        child: BowlBuilderLiveMetrics(),
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    AnimatedSwitcher(
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
                            ? Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.xl,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    const AspectRatio(
                                      aspectRatio: 1,
                                      child: ClipRRect(
                                        borderRadius: AppRadius.kLarge,
                                        child: ColoredBox(
                                          color: AppColors.background,
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
                                    const SizedBox(height: AppSpacing.xl),
                                  ],
                                ),
                              )
                            : _IngredientCarousel(category: currentCategory!),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BowlBuilderActionBar(
        isSummary: isSummaryStep,
        grandTotal: grandTotal,
        totalCalories: totalCalories,
        totalProtein: totalProtein,
        onPrimaryAction: isSummaryStep
            ? () => _addToCart(context, ref)
            : () => ref
                .read(bowlBuilderProvider.notifier)
                .goToStep(BowlBuilderStep.summary),
      ),
    );
  }
}

/// One category's ingredient list — a fixed-card-width horizontal
/// carousel (`IngredientCard.width`) that shows ~2.2–2.6 cards on a phone
/// viewport and simply more of them on a wider one, with no separate
/// breakpoint/grid layout needed (v2 redesign, replaces the old
/// `SliverGrid`-based `_CategoryStepBody`).
///
/// No category is required and none has a cap, so this is purely a
/// rendering choice: Proteinler/Karbonhidratlar cards show an always-visible
/// +/- stepper once selected (the same ingredient can be added any number of
/// times); every other category's cards are a single tap-to-toggle (one
/// portion, tap again to remove, unlimited distinct ingredients).
class _IngredientCarousel extends ConsumerWidget {
  final BowlBuilderCategory category;

  static const double _carouselHeight = 400;

  const _IngredientCarousel({required this.category});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(bowlBuilderCatalogRepositoryProvider);
    final state = ref.watch(bowlBuilderProvider);
    final notifier = ref.read(bowlBuilderProvider.notifier);
    final ingredients = catalog.ingredientsFor(category.id);
    final displayName = category.displayName ?? category.name;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$displayName Seç',
                style: AppTypography.titleLarge.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              // Only where behavior genuinely differs — quantity
              // categories let you add the same ingredient more than
              // once; every other category doesn't need this explained.
              if (category.allowsQuantity) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Birden fazla porsiyon ekleyebilirsin.',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          height: _carouselHeight,
          child: ListView.separated(
            key: const Key('ingredientCarouselListView'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            itemCount: ingredients.length,
            separatorBuilder: (context, index) =>
                const SizedBox(width: AppSpacing.md),
            itemBuilder: (context, index) {
              final ingredient = ingredients[index];
              return RepaintBoundary(
                child: category.allowsQuantity
                    ? IngredientCard(
                        name: ingredient.name,
                        price: ingredient.price,
                        imageKey: ingredient.imageKey,
                        quantity: state.quantityFor(ingredient.id),
                        allowsQuantity: true,
                        caloriesKcal: ingredient.caloriesKcal,
                        proteinGrams: ingredient.proteinGrams,
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
                        caloriesKcal: ingredient.caloriesKcal,
                        proteinGrams: ingredient.proteinGrams,
                        onTap: () => notifier.toggleIngredient(ingredient.id),
                      ),
              );
            },
          ),
        ),
      ],
    );
  }
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
