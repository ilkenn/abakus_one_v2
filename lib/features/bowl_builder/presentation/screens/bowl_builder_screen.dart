import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
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
import '../widgets/build_your_bowl_hero.dart';
import '../widgets/builder_summary.dart';
import '../widgets/ingredient_card.dart';

/// Bowl Builder v2 — category-driven redesign (2026-08-08). Replaces the
/// old linear "Adım N/9" wizard (`BuilderProgress`, forced Geri/Devam Et)
/// with free-roaming navigation: a horizontal category selector the
/// customer can jump around in at any time, a compact hero, and a
/// persistent bottom action bar. The underlying state machine —
/// `BowlBuilderStep`, `bowlBuilderProvider`'s selection/quantity/pricing
/// rules, cart and recipe-snapshot wiring — is unchanged; this screen
/// only reinterprets `state.currentStep` as "which category is active"
/// instead of "which step of a linear form".
///
/// The main editing screen's hero is [BuildYourBowlHero] — a static
/// approved banner (Bowl Builder Static Hero task, 2026-08-08).
///
/// B.1 (2026-08-17): while picking, `BowlBuilderLiveMetrics`'s full
/// dashboard (price/kcal/protein/fat/carbs/count) no longer renders here
/// at all — only `BowlBuilderActionBar`'s pinned, condensed price/kcal/
/// protein readout is visible during picking, so there is exactly one
/// nutrition summary on screen at a time.
///
/// B.3 (2026-08-18): the visual bowl/canvas preview on the review step is
/// cancelled (product decision) — `BowlCanvas` is no longer rendered
/// anywhere in *this screen*. Tapping "Bowlu İncele" now leads straight
/// into `BuilderSummary`'s information-focused review (macro summary →
/// allergens → selected ingredients → quantity/note), which owns the
/// single nutrition summary shown on that step. `BowlCanvas` itself is
/// untouched and not deleted — it's still a real, separate consumer of
/// `CartScreen`'s "Kendi Bowlun" line thumbnail, so it stays a live
/// component, just no longer reachable from Bowl Builder's own flow (no
/// bowl/layer image assets exist yet regardless; see the B.0 audit —
/// this was already true before B.3, for every caller).
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
    // B.1: narrowed from a full `ref.watch(bowlBuilderProvider)` — this
    // build method only ever reads `currentStep`/`quantity` off that
    // state (verified: nothing else from `state` appears below; `note`/
    // `selectedQuantitiesByIngredient` are read via `ref.read` inside
    // `_addToCart`, not here). A `setNote` keystroke on the Summary step
    // no longer rebuilds this whole screen as a result.
    final currentStep = ref.watch(
      bowlBuilderProvider.select((state) => state.currentStep),
    );
    final quantity = ref.watch(
      bowlBuilderProvider.select((state) => state.quantity),
    );
    final catalog = ref.watch(bowlBuilderCatalogRepositoryProvider);
    final grandTotal = ref.watch(bowlBuilderGrandTotalProvider);
    final totalCalories = ref.watch(bowlBuilderTotalCaloriesProvider);
    final totalProtein = ref.watch(bowlBuilderTotalProteinProvider);
    final selectedModifiers = ref.watch(bowlBuilderSelectedModifiersProvider);

    final isSummaryStep = currentStep == BowlBuilderStep.summary;
    final currentCategory =
        isSummaryStep ? null : _categoryById(catalog, currentStep.name);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kendi Bowlunu Yarat'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          // B.3.4: on Summary, back returns to ingredient picking
          // (preserving every selection) instead of popping the whole
          // screen — the same action as "Seçimleri Düzenle". Picking-mode
          // back behavior is unchanged.
          onPressed: () {
            if (isSummaryStep) {
              ref.read(bowlBuilderProvider.notifier).returnToPicking();
            } else {
              Navigator.pop(context);
            }
          },
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
            // Always jumpable during picking — no forced linear
            // progression through categories. B.1: vertical padding
            // tightened (md → sm) as part of the overall rhythm pass.
            //
            // B.3.3 (2026-08-18): hidden entirely on the Summary/review
            // step — the customer is no longer picking, so a row of
            // category chips here just wastes vertical space and makes
            // "Sipariş Özeti" read as still-editable. Category grouping
            // inside `BuilderSummary`'s "Seçilen Malzemeler" section is
            // unaffected — that's driven by `catalog.categories` directly,
            // not by this selector's presence.
            if (!isSummaryStep)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                  vertical: AppSpacing.sm,
                ),
                child: BowlBuilderCategorySelector(
                  categories: catalog.categories,
                  currentStep: currentStep,
                  onCategorySelected: (step) =>
                      ref.read(bowlBuilderProvider.notifier).goToStep(step),
                ),
              ),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Compact static editorial hero — hidden on the
                    // summary step, which shows BuilderSummary's
                    // information-focused review instead (B.3: no bowl
                    // visual preview on that step anymore either).
                    //
                    // B.1: the picking-step full BowlBuilderLiveMetrics
                    // dashboard that used to sit directly under the hero
                    // is gone — LOCKED decision: during picking, the
                    // pinned BowlBuilderActionBar's price/kcal/protein
                    // readout is the only nutrition summary on screen;
                    // the full macro breakdown stays exclusively on the
                    // Summary step's BuilderSummary, so there is never
                    // more than one nutrition summary visible at a time.
                    if (!isSummaryStep) ...[
                      const Padding(
                        padding: EdgeInsets.fromLTRB(
                          AppSpacing.xl,
                          0,
                          AppSpacing.xl,
                          AppSpacing.sm,
                        ),
                        child: BuildYourBowlHero(),
                      ),
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
                        key: ValueKey(currentStep),
                        child: isSummaryStep
                            ? Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.xl,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    // B.3: the live BowlCanvas preview is
                                    // cancelled (product decision) — the
                                    // review step now leads straight into
                                    // BuilderSummary's own information
                                    // hierarchy instead of a bowl visual.
                                    BuilderSummary(
                                      selectedModifiers: selectedModifiers,
                                      categories: catalog.categories,
                                      quantity: quantity,
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
                                      onEditSelections: () => ref
                                          .read(bowlBuilderProvider.notifier)
                                          .returnToPicking(),
                                    ),
                                    const SizedBox(height: AppSpacing.xl),
                                  ],
                                ),
                              )
                            : _IngredientCarousel(
                                category: currentCategory!,
                                isFirstCategory:
                                    catalog.categories.isNotEmpty &&
                                        currentCategory.id ==
                                            catalog.categories.first.id,
                              ),
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
        hasSelection: selectedModifiers.isNotEmpty,
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
/// carousel (`IngredientCard.width`) that shows ~2.4–2.8 cards on a phone
/// viewport and simply more of them on a wider one, with no separate
/// breakpoint/grid layout needed (v2 redesign, replaces the old
/// `SliverGrid`-based `_CategoryStepBody`).
///
/// No category is required and none has a cap, so this is purely a
/// rendering choice: Proteinler/Karbonhidratlar cards show an always-visible
/// +/- stepper once selected (the same ingredient can be added any number of
/// times); every other category's cards are a single tap-to-toggle (one
/// portion, tap again to remove, unlimited distinct ingredients).
///
/// B.2 (2026-08-17):
/// - Row height cut 400 → 248 (`_rowHeight`) to match `IngredientCard`'s
///   own B.2 compaction — the old fixed height left significant unused
///   space below every card regardless of content.
/// - Each card now watches only its own quantity via `bowlBuilderProvider
///   .select((s) => s.quantityFor(ingredient.id))` inside a per-item
///   `Consumer`, instead of this whole carousel watching the full
///   `bowlBuilderProvider` state and recomputing every card's props on any
///   selection change anywhere. Toggling one ingredient now only rebuilds
///   that one card.
/// - Adds horizontal-scroll discoverability: a right-edge fade + chevron
///   (hidden once the row is scrolled to its end), a left chevron that
///   only appears after the row has been scrolled away from the start,
///   and a one-time "Daha fazla seçenek için yana kaydır" hint — shown
///   only for the catalog's first category, and only until the customer
///   actually scrolls, never repeated after that on any category.
class _IngredientCarousel extends ConsumerStatefulWidget {
  final BowlBuilderCategory category;
  final bool isFirstCategory;

  static const double _rowHeight = 248;

  const _IngredientCarousel({
    required this.category,
    required this.isFirstCategory,
  });

  @override
  ConsumerState<_IngredientCarousel> createState() =>
      _IngredientCarouselState();
}

class _IngredientCarouselState extends ConsumerState<_IngredientCarousel> {
  final ScrollController _scrollController = ScrollController();
  bool _canScrollLeft = false;
  bool _canScrollRight = false;
  bool _hasScrolled = false;

  /// How far a chevron tap moves the row — roughly two cards' worth,
  /// a "sensible amount" rather than a single-card nudge or a full jump
  /// to the end.
  static const double _scrollStep = (IngredientCard.width + AppSpacing.md) * 2;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateScrollAffordance);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateScrollAffordance();
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateScrollAffordance);
    _scrollController.dispose();
    super.dispose();
  }

  void _updateScrollAffordance() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    // A small dead-zone (not exactly 0) avoids the chevron flickering in
    // and out from sub-pixel scroll-physics settling right at either end.
    final canLeft = position.pixels > 4;
    final canRight = position.pixels < position.maxScrollExtent - 4;
    if (canLeft != _canScrollLeft ||
        canRight != _canScrollRight ||
        (canLeft && !_hasScrolled)) {
      setState(() {
        _canScrollLeft = canLeft;
        _canScrollRight = canRight;
        if (canLeft) _hasScrolled = true;
      });
    }
  }

  void _scrollBy(double delta) {
    if (!_scrollController.hasClients) return;
    final target = (_scrollController.offset + delta)
        .clamp(0.0, _scrollController.position.maxScrollExtent);
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(bowlBuilderCatalogRepositoryProvider);
    final notifier = ref.read(bowlBuilderProvider.notifier);
    final ingredients = catalog.ingredientsFor(widget.category.id);
    final displayName = widget.category.displayName ?? widget.category.name;
    final showHint =
        widget.isFirstCategory && !_hasScrolled && ingredients.length > 2;

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
              if (widget.category.allowsQuantity) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Birden fazla porsiyon ekleyebilirsin.',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
              // First-use scroll hint — one category, one time, gone the
              // instant the customer actually scrolls. Never a modal, never
              // repeated per-category.
              if (showHint) ...[
                const SizedBox(height: AppSpacing.xs),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.swipe_rounded,
                      size: 14,
                      color: AppColors.textSecondary.withValues(alpha: 0.8),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Daha fazla seçenek için yana kaydır',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          height: _IngredientCarousel._rowHeight,
          child: Stack(
            children: [
              ListView.separated(
                key: const Key('ingredientCarouselListView'),
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                itemCount: ingredients.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(width: AppSpacing.md),
                itemBuilder: (context, index) {
                  final ingredient = ingredients[index];
                  return RepaintBoundary(
                    child: Consumer(
                      builder: (context, ref, _) {
                        // Scoped to exactly this ingredient's quantity —
                        // selecting a different ingredient never rebuilds
                        // this card.
                        final quantity = ref.watch(
                          bowlBuilderProvider.select(
                            (state) => state.quantityFor(ingredient.id),
                          ),
                        );
                        return widget.category.allowsQuantity
                            ? IngredientCard(
                                name: ingredient.name,
                                price: ingredient.price,
                                imageKey: ingredient.imageKey,
                                quantity: quantity,
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
                                quantity: quantity,
                                allowsQuantity: false,
                                caloriesKcal: ingredient.caloriesKcal,
                                proteinGrams: ingredient.proteinGrams,
                                onTap: () =>
                                    notifier.toggleIngredient(ingredient.id),
                              );
                      },
                    ),
                  );
                },
              ),
              if (_canScrollRight)
                const _EdgeFade(alignment: Alignment.centerRight),
              if (_canScrollLeft)
                const _EdgeFade(alignment: Alignment.centerLeft),
              if (_canScrollRight)
                _ScrollChevron(
                  alignment: Alignment.centerRight,
                  icon: Icons.chevron_right_rounded,
                  semanticLabel: 'Sağa kaydır',
                  onTap: () => _scrollBy(_scrollStep),
                ),
              if (_canScrollLeft)
                _ScrollChevron(
                  alignment: Alignment.centerLeft,
                  icon: Icons.chevron_left_rounded,
                  semanticLabel: 'Sola kaydır',
                  onTap: () => _scrollBy(-_scrollStep),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A thin, pointer-transparent gradient hinting that content continues
/// past this edge — subtle by design (fades into the screen's own
/// background, never a hard line), never covers card content since it
/// sits only in the outer ~32px of the row.
class _EdgeFade extends StatelessWidget {
  final Alignment alignment;

  const _EdgeFade({required this.alignment});

  @override
  Widget build(BuildContext context) {
    final isRight = alignment == Alignment.centerRight;
    return Positioned(
      top: 0,
      bottom: 0,
      right: isRight ? 0 : null,
      left: isRight ? null : 0,
      width: 32,
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: isRight ? Alignment.centerLeft : Alignment.centerRight,
              end: isRight ? Alignment.centerRight : Alignment.centerLeft,
              colors: [
                AppColors.background.withValues(alpha: 0.0),
                AppColors.background,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A small, restrained "more content this way" affordance — never covers
/// card content (sits centered in the row's own edge fade, outside any
/// card's tap area) and carries a real accessible tap target/label even
/// though its visible icon stays compact.
class _ScrollChevron extends StatelessWidget {
  final Alignment alignment;
  final IconData icon;
  final String semanticLabel;
  final VoidCallback onTap;

  const _ScrollChevron({
    required this.alignment,
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      bottom: 0,
      right: alignment == Alignment.centerRight ? 0 : null,
      left: alignment == Alignment.centerLeft ? 0 : null,
      child: Center(
        child: Semantics(
          button: true,
          label: semanticLabel,
          child: Material(
            color: AppColors.surface.withValues(alpha: 0.92),
            shape: const CircleBorder(),
            elevation: 1,
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              child: SizedBox(
                // 44x44 — a real comfortable tap target even though the
                // visible circle/icon inside reads smaller and lighter.
                width: 44,
                height: 44,
                child: Icon(
                  icon,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
            ),
          ),
        ),
      ),
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
