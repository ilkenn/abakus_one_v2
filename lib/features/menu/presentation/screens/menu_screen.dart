import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme_constants.dart';
import '../../../../shared/widgets/cards/bowl_builder_feature_card.dart';
import '../../../../shared/widgets/images/product_image.dart';
import '../../../bowl_builder/presentation/screens/bowl_builder_screen.dart';
import '../../../cart/presentation/providers/cart_provider.dart';
import '../../../cart/presentation/providers/shopping_channel_provider.dart';
import '../../../favorites/presentation/providers/favorites_provider.dart';
import '../../../qr/presentation/widgets/table_context_badge.dart';
import '../../../restaurant/presentation/providers/restaurant_status_provider.dart';
import '../../domain/models/menu_product.dart';
import '../../domain/pricing/channel_pricing_policy.dart';
import '../providers/channel_price_display_provider.dart';
import '../providers/menu_catalog_provider.dart';
import '../providers/menu_filter_provider.dart';
import 'product_detail_screen.dart';

const String _allCategoriesLabel = 'Tümü';

class MenuScreen extends ConsumerStatefulWidget {
  const MenuScreen({super.key});

  @override
  ConsumerState<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends ConsumerState<MenuScreen> {
  String _searchQuery = '';
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(menuCategoriesProvider);
    final allProducts = ref.watch(menuProductsProvider);
    final selectedFilter = ref.watch(menuFilterProvider);
    final isRestaurantOpen = ref.watch(
      restaurantStatusProvider.select((s) => s.isOpen && s.acceptsOrders),
    );

    // A filter set from elsewhere (e.g. Home's quick-category chips) that
    // no longer matches a real category name is treated as "no filter"
    // rather than silently showing an empty list.
    final selectedCategory = categories
        .where((category) => category.name == selectedFilter)
        .toList();
    final isAllSelected =
        selectedFilter == _allCategoriesLabel || selectedCategory.isEmpty;

    final query = _searchQuery.trim().toLowerCase();
    final filteredProducts = allProducts.where((product) {
      final matchesCategory =
          isAllSelected || product.categoryId == selectedCategory.first.id;
      final matchesQuery = query.isEmpty ||
          product.name.toLowerCase().contains(query) ||
          product.description.toLowerCase().contains(query);
      return matchesCategory && matchesQuery;
    }).toList();

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.xl,
                right: AppSpacing.xl,
                top: AppSpacing.xl,
                bottom: AppSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Menü', style: AppTypography.headlineMedium),
                      _RestaurantStatusPill(isOpen: isRestaurantOpen),
                    ],
                  ),
                  const TableContextBadge(),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _searchQuery = value),
                    decoration: InputDecoration(
                      hintText: 'Ürün veya malzeme ara...',
                      hintStyle: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: AppColors.textSecondary,
                      ),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(
                                Icons.clear_rounded,
                                color: AppColors.textSecondary,
                              ),
                              onPressed: () {
                                setState(() {
                                  _searchController.clear();
                                  _searchQuery = '';
                                });
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: AppColors.surfaceVariant,
                      border: const OutlineInputBorder(
                        borderRadius: AppRadius.kMedium,
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.md,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: BowlBuilderFeatureCard(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const BowlBuilderScreen(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              height: AppThemeConstants.categoryListHeight,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                itemCount: categories.length + 1,
                itemBuilder: (context, index) {
                  final isAllChip = index == 0;
                  final categoryName = isAllChip
                      ? _allCategoriesLabel
                      : categories[index - 1].name;
                  final isSelected = isAllChip
                      ? isAllSelected
                      : !isAllSelected && categoryName == selectedFilter;

                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                    ),
                    child: _CategoryChip(
                      label: categoryName,
                      isSelected: isSelected,
                      onTap: () => ref
                          .read(menuFilterProvider.notifier)
                          .setFilter(categoryName),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: filteredProducts.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.search_off_rounded,
                            size: 48,
                            color: AppColors.textSecondary.withValues(
                              alpha: 0.5,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            'Aramanızla eşleşen ürün bulunamadı.',
                            style: AppTypography.bodyLarge.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xl,
                        vertical: AppSpacing.md,
                      ),
                      itemCount: filteredProducts.length,
                      itemBuilder: (context, index) {
                        final product = filteredProducts[index];
                        return RepaintBoundary(
                          child: _ProductListCard(product: product),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RestaurantStatusPill extends StatelessWidget {
  final bool isOpen;

  const _RestaurantStatusPill({required this.isOpen});

  @override
  Widget build(BuildContext context) {
    final color = isOpen ? AppColors.success : AppColors.error;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: AppRadius.kPill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            isOpen ? 'Açık' : 'Kapalı',
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppThemeConstants.categoryTransitionDuration,
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.surfaceVariant,
          borderRadius: AppRadius.kMedium,
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: AppThemeConstants.categoryTransitionDuration,
            curve: Curves.easeInOut,
            style: AppTypography.labelLarge.copyWith(
              color: isSelected ? AppColors.onPrimary : AppColors.textPrimary,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
            child: Text(label),
          ),
        ),
      ),
    );
  }
}

class _ProductListCard extends ConsumerStatefulWidget {
  final MenuProduct product;

  const _ProductListCard({required this.product});

  @override
  ConsumerState<_ProductListCard> createState() => _ProductListCardState();
}

class _ProductListCardState extends ConsumerState<_ProductListCard> {
  bool _isPressed = false;

  void _openDetail() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProductDetailScreen(product: widget.product),
      ),
    );
  }

  void _quickAddToCart() {
    final product = widget.product;
    // A product with modifier groups needs Product Detail's selection UI —
    // adding it directly here would silently skip required choices instead
    // of enforcing them.
    if (product.modifierGroups.isNotEmpty) {
      _openDetail();
      return;
    }
    final channelContext = ref.read(shoppingChannelProvider);
    final policy = ref.read(channelPricingPolicySnapshotProvider).valueOrNull ??
        const ChannelPricingPolicy();
    ref.read(cartProvider.notifier).addToCart(
          id: product.id,
          name: product.name,
          desc: product.description,
          price: resolveDisplayPrice(
            product: product,
            channelContext: channelContext,
            policy: policy,
          ),
          pricedForChannel: channelContext.channel,
        );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${product.name} sepete eklendi!'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final isFavorite = ref.watch(
      favoritesProvider.select(
        (state) => state.items.any((item) => item.productId == product.id),
      ),
    );
    final channelContext = ref.watch(shoppingChannelProvider);
    final policy =
        ref.watch(channelPricingPolicySnapshotProvider).valueOrNull ??
            const ChannelPricingPolicy();
    final displayPrice = resolveDisplayPrice(
      product: product,
      channelContext: channelContext,
      policy: policy,
    );

    return AnimatedScale(
      scale: _isPressed ? 0.98 : 1.0,
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOut,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.xl),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.kLarge,
          boxShadow: AppShadows.card,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: AppRadius.kLarge,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTapDown: (_) => setState(() => _isPressed = true),
            onTapCancel: () => setState(() => _isPressed = false),
            onTap: () {
              setState(() => _isPressed = false);
              _openDetail();
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    ProductImage(
                      imageKey: product.imageKey,
                      width: double.infinity,
                      height: 210,
                      borderRadius: BorderRadius.zero,
                      placeholderIconSize: 56,
                      heroTag: 'product_image_${product.id}',
                    ),
                    Positioned(
                      top: AppSpacing.sm,
                      right: AppSpacing.sm,
                      child: Material(
                        color: AppColors.overlay,
                        shape: const CircleBorder(),
                        child: IconButton(
                          constraints: const BoxConstraints(
                            minWidth: AppThemeConstants.minTapTargetSize,
                            minHeight: AppThemeConstants.minTapTargetSize,
                          ),
                          tooltip: isFavorite
                              ? 'Favorilerden çıkar'
                              : 'Favorilere ekle',
                          onPressed: () {
                            ref
                                .read(favoritesProvider.notifier)
                                .toggleFavorite(product.id);
                          },
                          icon: Icon(
                            isFavorite
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            color: isFavorite ? AppColors.error : Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        style: AppTypography.titleLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        product.description,
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${displayPrice.toStringAsFixed(0)} TL',
                            style: AppTypography.priceLarge,
                          ),
                          IconButton.filled(
                            tooltip: 'Sepete ekle',
                            onPressed: _quickAddToCart,
                            style: IconButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: AppColors.onPrimary,
                              shape: const RoundedRectangleBorder(
                                borderRadius: AppRadius.kSmall,
                              ),
                              padding: const EdgeInsets.all(AppSpacing.xs),
                              minimumSize: const Size(
                                AppThemeConstants.minTapTargetSize,
                                AppThemeConstants.minTapTargetSize,
                              ),
                            ),
                            icon: const Icon(
                              Icons.add_shopping_cart_rounded,
                              size: 18,
                            ),
                          ),
                        ],
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
