import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme_constants.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/option_selection_card.dart';
import '../../../../shared/widgets/images/product_image.dart';
import '../../../../shared/widgets/layout/app_section_header.dart';
import '../../../cart/presentation/providers/cart_provider.dart';
import '../../../cart/presentation/providers/shopping_channel_provider.dart';
import '../../../favorites/presentation/providers/favorites_provider.dart';
import '../../domain/models/menu_product.dart';
import '../../domain/models/modifier_group.dart';
import '../../domain/models/product_nutrition.dart';
import '../../domain/models/selected_modifier.dart';
import '../../domain/pricing/channel_pricing_policy.dart';
import '../providers/channel_price_display_provider.dart';

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

  void _increment() => setState(() => _quantity++);

  void _decrement() => setState(() {
        if (_quantity > 1) _quantity--;
      });

  void _selectSingle(ModifierGroup group, String optionId) {
    setState(() {
      final current = _selections[group.id] ?? const [];
      _selections[group.id] = (current.length == 1 && current.first == optionId)
          ? const []
          : [optionId];
    });
  }

  void _toggleMultiple(ModifierGroup group, String optionId) {
    setState(() {
      final current = List<String>.from(_selections[group.id] ?? const []);
      if (current.contains(optionId)) {
        current.remove(optionId);
      } else {
        if (current.length >= group.maxSelections) return;
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

    ref.read(cartProvider.notifier).addToCart(
          id: widget.product.id,
          name: widget.product.name,
          desc: widget.product.description,
          price: _resolvedBasePrice,
          quantity: _quantity,
          selectedModifiers: _selectedModifiers,
          note: _noteController.text.trim(),
          pricedForChannel: ref.read(shoppingChannelProvider).channel,
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
