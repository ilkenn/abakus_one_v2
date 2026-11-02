import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_constants.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/qr_menu_theme.dart';
import '../../../../shared/widgets/cards/option_selection_card.dart';
import '../../../../shared/widgets/images/product_image.dart';
import '../../../../shared/widgets/layout/app_section_header.dart';
import '../../../cart/presentation/providers/cart_provider.dart';
import '../../../qr/presentation/widgets/table_context_badge.dart';
import '../../../cart/presentation/providers/shopping_channel_provider.dart';
import '../../../favorites/presentation/providers/favorites_provider.dart';
import '../../domain/models/menu_product.dart';
import '../../domain/models/modifier_group.dart';
import '../../domain/models/product_nutrition.dart';
import '../../domain/models/selected_modifier.dart';
import '../../domain/pricing/channel_pricing_policy.dart';
import '../providers/channel_price_display_provider.dart';
import '../providers/menu_catalog_provider.dart';
import '../providers/product_pairing_provider.dart';

class ProductDetailScreen extends ConsumerStatefulWidget {
  final MenuProduct product;

  const ProductDetailScreen({super.key, required this.product});

  @override
  ConsumerState<ProductDetailScreen> createState() =>
      _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen>
    with SingleTickerProviderStateMixin {
  int _quantity = 1;
  late final TextEditingController _noteController;
  final Map<String, List<String>> _selections = {};
  final Set<String> _excludedIngredients = {};
  late final AnimationController _entryController;
  late final Animation<double> _entryFade;
  late final Animation<Offset> _entrySlide;

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController();
    for (final group in widget.product.modifierGroups) {
      final defaults =
          group.options.where((o) => o.isDefault).map((o) => o.id).toList();
      if (defaults.isNotEmpty) _selections[group.id] = defaults;
    }
    // A one-shot, subtle entrance for the whole screen — not a loading
    // state (there's no async boundary here, the product is already in
    // hand), just a premium arrival feel. Runs once and stays complete.
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    )..forward();
    _entryFade = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOut,
    );
    _entrySlide = Tween<Offset>(
      begin: const Offset(0, 0.03),
      end: Offset.zero,
    ).animate(_entryFade);
  }

  @override
  void dispose() {
    _noteController.dispose();
    _entryController.dispose();
    super.dispose();
  }

  void _increment() {
    HapticFeedback.selectionClick();
    setState(() => _quantity++);
  }

  void _decrement() {
    if (_quantity <= 1) return;
    HapticFeedback.selectionClick();
    setState(() => _quantity--);
  }

  void _selectSingle(ModifierGroup group, String optionId) {
    HapticFeedback.selectionClick();
    setState(() {
      final current = _selections[group.id] ?? const [];
      _selections[group.id] = (current.length == 1 && current.first == optionId)
          ? const []
          : [optionId];
    });
  }

  void _toggleExcludedIngredient(String ingredient) {
    HapticFeedback.selectionClick();
    setState(() {
      if (!_excludedIngredients.remove(ingredient)) {
        _excludedIngredients.add(ingredient);
      }
    });
  }

  void _toggleMultiple(ModifierGroup group, String optionId) {
    final current = List<String>.from(_selections[group.id] ?? const []);
    if (!current.contains(optionId) && current.length >= group.maxSelections) {
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      if (current.contains(optionId)) {
        current.remove(optionId);
      } else {
        current.add(optionId);
      }
      _selections[group.id] = current;
    });
  }

  bool get _allGroupsValid => widget.product.modifierGroups
      .every((group) => group.isSatisfiedBy(_selections[group.id] ?? const []));

  List<SelectedModifier> get _selectedModifiers {
    final result = <SelectedModifier>[];
    for (final group in widget.product.modifierGroups) {
      final selectedIds = _selections[group.id] ?? const [];
      for (final option in group.options) {
        if (selectedIds.contains(option.id)) {
          result.add(SelectedModifier(
            groupId: group.id,
            groupName: group.name,
            optionId: option.id,
            optionName: option.name,
            extraPrice: option.extraPrice,
          ));
        }
      }
    }
    return result;
  }

  /// The channel-resolved single-unit base price (before modifiers) —
  /// [widget.product.basePrice] unchanged outside Gel Al, the resolved
  /// takeaway price when shopping under it. `ref.watch` here (not
  /// `.read`) so this screen re-renders if the policy snapshot resolves
  /// after the widget already built.
  double get _resolvedBasePrice {
    final channelContext = ref.watch(shoppingChannelProvider);
    final policy =
        ref.watch(channelPricingPolicySnapshotProvider).valueOrNull ??
            const ChannelPricingPolicy();
    return resolveDisplayPrice(
      product: widget.product,
      channelContext: channelContext,
      policy: policy,
    );
  }

  double get _unitPrice =>
      _resolvedBasePrice +
      _selectedModifiers.fold(0.0, (sum, m) => sum + m.extraPrice);

  double get _totalPrice => _unitPrice * _quantity;

  void _addToCart() {
    if (!_allGroupsValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lütfen zorunlu seçimleri tamamlayın.'),
        ),
      );
      return;
    }

    HapticFeedback.lightImpact();
    ref.read(cartProvider.notifier).addToCart(
          id: widget.product.id,
          name: widget.product.name,
          desc: widget.product.description,
          price: _resolvedBasePrice,
          quantity: _quantity,
          selectedModifiers: _selectedModifiers,
          note: _noteController.text.trim(),
          pricedForChannel: ref.read(shoppingChannelProvider).channel,
          removedIngredients: _excludedIngredients.toList(),
        );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${widget.product.name} sepete eklendi!'),
        duration: const Duration(seconds: 1),
      ),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isFav = ref.watch(
      favoritesProvider.select(
        (state) =>
            state.items.any((item) => item.productId == widget.product.id),
      ),
    );
    final nutrition = widget.product.nutrition;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            tooltip: isFav ? 'Favorilerden çıkar' : 'Favorilere ekle',
            onPressed: () => ref
                .read(favoritesProvider.notifier)
                .toggleFavorite(widget.product.id),
            icon: Icon(
              isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: isFav ? AppColors.error : AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: Column(
        children: [
          Expanded(
            child: FadeTransition(
              opacity: _entryFade,
              child: SlideTransition(
                position: _entrySlide,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ProductImage(
                        heroTag: 'product_image_${widget.product.id}',
                        imageKey: widget.product.imageKey,
                        categoryId: widget.product.categoryId,
                        width: double.infinity,
                        height: 320,
                        borderRadius: BorderRadius.zero,
                        placeholderIconSize: 88,
                      ),
                      Padding(
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const TableContextBadge(),
                            Text(
                              widget.product.name,
                              style: AppTypography.headlineMedium,
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              '${_resolvedBasePrice.toStringAsFixed(0)} TL',
                              style: AppTypography.priceLarge,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Text(
                              widget.product.description,
                              style: AppTypography.bodyLarge.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                            if (nutrition != null && nutrition.hasAnyValue) ...[
                              const SizedBox(height: AppSpacing.md),
                              _NutritionRow(nutrition: nutrition),
                            ],
                            if (widget
                                .product.removableIngredients.isNotEmpty) ...[
                              const Divider(height: AppSpacing.xxl),
                              const AppSectionHeader(
                                title: 'İçinden Çıkar',
                                subtitle:
                                    'İstemediğiniz malzemeleri işaretleyin.',
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              for (final ingredient
                                  in widget.product.removableIngredients)
                                Padding(
                                  padding: const EdgeInsets.only(
                                      bottom: AppSpacing.sm),
                                  child: OptionSelectionCard(
                                    name: '$ingredient İstemiyorum',
                                    extraPrice: 0,
                                    isSelected: _excludedIngredients
                                        .contains(ingredient),
                                    onTap: () =>
                                        _toggleExcludedIngredient(ingredient),
                                  ),
                                ),
                            ],
                            for (final group
                                in widget.product.modifierGroups) ...[
                              const Divider(height: AppSpacing.xxl),
                              AppSectionHeader(
                                title: group.name,
                                isRequired: group.isRequired,
                                subtitle: group.isRequired
                                    ? (group.maxSelections == 1
                                        ? 'Bir seçim yapınız.'
                                        : 'En az ${group.minSelections}, en fazla ${group.maxSelections} seçim yapınız.')
                                    : 'En fazla ${group.maxSelections} seçim yapabilirsiniz.',
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              for (final option in group.options)
                                Padding(
                                  padding: const EdgeInsets.only(
                                      bottom: AppSpacing.sm),
                                  child: OptionSelectionCard(
                                    name: option.name,
                                    extraPrice: option.extraPrice,
                                    isSelected:
                                        (_selections[group.id] ?? const [])
                                            .contains(option.id),
                                    onTap: () {
                                      if (group.selectionType ==
                                          ModifierSelectionType.single) {
                                        _selectSingle(group, option.id);
                                      } else {
                                        _toggleMultiple(group, option.id);
                                      }
                                    },
                                  ),
                                ),
                            ],
                            _SmartPairingSection(product: widget.product),
                            _DrinkCrossSellSection(product: widget.product),
                            const Divider(height: AppSpacing.xxl),
                            Text(
                              'Sipariş Notu',
                              style: AppTypography.titleMedium
                                  .copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            TextField(
                              controller: _noteController,
                              maxLength: 200,
                              maxLines: 2,
                              decoration: const InputDecoration(
                                hintText: 'Ürünle ilgili bir not ekleyin...',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(AppSpacing.xl),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              boxShadow: AppShadows.modal,
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Adet', style: AppTypography.titleMedium),
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.border),
                          borderRadius: AppRadius.kPill,
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              onPressed: _decrement,
                              icon: const Icon(Icons.remove_rounded),
                              color: AppColors.textSecondary,
                              constraints: const BoxConstraints(
                                minWidth: AppThemeConstants.minTapTargetSize,
                                minHeight: AppThemeConstants.minTapTargetSize,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                              ),
                              child: Text(
                                '$_quantity',
                                style: AppTypography.titleMedium,
                              ),
                            ),
                            IconButton(
                              onPressed: _increment,
                              icon: const Icon(Icons.add_rounded),
                              color: AppColors.primary,
                              constraints: const BoxConstraints(
                                minWidth: AppThemeConstants.minTapTargetSize,
                                minHeight: AppThemeConstants.minTapTargetSize,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Toplam Tutar',
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 150),
                              child: Text(
                                '${_totalPrice.toStringAsFixed(0)} TL',
                                key: ValueKey(_totalPrice),
                                style: AppTypography.priceLarge,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: _allGroupsValid ? _addToCart : null,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.md,
                            ),
                          ),
                          icon: const Icon(
                            Icons.add_shopping_cart_rounded,
                            size: 18,
                          ),
                          label: const Text('Sepete Ekle'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Bununla İyi Gider" — client-side-only Smart Pairing, per
/// [productPairingProvider]/`ProductPairingService`'s documented
/// complementary-category heuristic. Hides itself entirely when the
/// heuristic has nothing to suggest (an unmapped/test-only category, or no
/// matching product in the active catalog) — never a dead-looking empty
/// section.
class _SmartPairingSection extends ConsumerWidget {
  final MenuProduct product;

  const _SmartPairingSection({required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggestions = ref.watch(productPairingProvider(product));
    if (suggestions.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: AppSpacing.xxl),
        Text('Bununla İyi Gider', style: QrMenuTypography.title),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 150,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: suggestions.length,
            itemBuilder: (context, index) {
              final suggestion = suggestions[index];
              return Padding(
                padding: const EdgeInsets.only(right: AppSpacing.md),
                child: _PairingSuggestionCard(product: suggestion),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PairingSuggestionCard extends StatelessWidget {
  final MenuProduct product;

  const _PairingSuggestionCard({required this.product});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${product.name}, ${product.basePrice.toStringAsFixed(0)} TL',
      child: Material(
        color: Colors.transparent,
        borderRadius: AppRadius.kLarge,
        child: InkWell(
          borderRadius: AppRadius.kLarge,
          onTap: () => Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => ProductDetailScreen(product: product),
            ),
          ),
          child: Container(
            width: 128,
            decoration: BoxDecoration(
              color: QrMenuColors.surface,
              borderRadius: AppRadius.kLarge,
              border: Border.all(color: QrMenuColors.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ProductImage(
                  imageKey: product.imageKey,
                  categoryId: product.categoryId,
                  width: 128,
                  height: 96,
                  borderRadius: BorderRadius.zero,
                  heroTag: 'pairing_product_image_${product.id}',
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        style: QrMenuTypography.bodySecondary.copyWith(
                          fontWeight: FontWeight.w600,
                          color: QrMenuColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${product.basePrice.toStringAsFixed(0)} TL',
                        // `primary`, not `terracotta` — Verified contrast:
                        // at this caption size/weight, terracotta-on-white
                        // is only 4.23:1 (below the 4.5:1 normal-text
                        // floor and not WCAG "large text"); primary-on-
                        // white is 12.30:1 (see `qr_menu_theme.dart`'s
                        // contrast log).
                        style: QrMenuTypography.caption.copyWith(
                          color: QrMenuColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Yanına En Çok Yakışanlar" — single-tap drink add-on, per
/// [drinkCrossSellProductsProvider]. Hides itself on a drink's own detail
/// page (suggesting a drink while looking at a drink reads as a mistake,
/// not a cross-sell) and whenever the catalog has none active.
class _DrinkCrossSellSection extends ConsumerWidget {
  final MenuProduct product;

  const _DrinkCrossSellSection({required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (product.categoryId == 'cat_icecekler') return const SizedBox.shrink();
    final drinks = ref.watch(drinkCrossSellProductsProvider);
    if (drinks.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: AppSpacing.xxl),
        Text('Yanına En Çok Yakışanlar', style: QrMenuTypography.title),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final drink in drinks) _DrinkQuickAddChip(drink: drink),
          ],
        ),
      ],
    );
  }
}

class _DrinkQuickAddChip extends ConsumerWidget {
  final MenuProduct drink;

  const _DrinkQuickAddChip({required this.drink});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Semantics(
      button: true,
      label:
          '${drink.name}, ${drink.basePrice.toStringAsFixed(0)} TL, sepete ekle',
      child: Material(
        color: QrMenuColors.surface,
        borderRadius: AppRadius.kPill,
        child: InkWell(
          borderRadius: AppRadius.kPill,
          onTap: () {
            HapticFeedback.lightImpact();
            ref.read(cartProvider.notifier).addToCart(
                  id: drink.id,
                  name: drink.name,
                  desc: drink.description,
                  price: drink.basePrice,
                  pricedForChannel: ref.read(shoppingChannelProvider).channel,
                );
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${drink.name} sepete eklendi!'),
                duration: const Duration(seconds: 1),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              borderRadius: AppRadius.kPill,
              border: Border.all(color: QrMenuColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.add_circle_outline_rounded,
                    size: 18, color: QrMenuColors.primary),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  '${drink.name} · ${drink.basePrice.toStringAsFixed(0)} TL',
                  style: QrMenuTypography.bodySecondary
                      .copyWith(color: QrMenuColors.textPrimary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NutritionRow extends StatelessWidget {
  final ProductNutrition nutrition;

  const _NutritionRow({required this.nutrition});

  @override
  Widget build(BuildContext context) {
    final entries = <String, String>{
      if (nutrition.calories != null) 'Kalori': '${nutrition.calories} kcal',
      if (nutrition.proteinGrams != null)
        'Protein': '${nutrition.proteinGrams!.toStringAsFixed(0)} g',
      if (nutrition.carbsGrams != null)
        'Karbonhidrat': '${nutrition.carbsGrams!.toStringAsFixed(0)} g',
      if (nutrition.fatGrams != null)
        'Yağ': '${nutrition.fatGrams!.toStringAsFixed(0)} g',
    };

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      children: entries.entries
          .map(
            (entry) => Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 4,
              ),
              decoration: const BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: AppRadius.kPill,
              ),
              child: Text(
                '${entry.key}: ${entry.value}',
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textSecondary),
              ),
            ),
          )
          .toList(),
    );
  }
}
