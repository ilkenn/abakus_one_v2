import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme_constants.dart';
import '../../../home/presentation/data/mock_data.dart';
import '../providers/favorites_provider.dart';
import '../../../cart/presentation/providers/cart_provider.dart';

class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favoriteState = ref.watch(favoritesProvider);
    const allProducts = HomeMockData.popularProducts;

    final favProducts = allProducts.where((product) {
      final productId = 'prod_${product['name'].hashCode}';
      return favoriteState.items.any((item) => item.productId == productId);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Favorilerim'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: SafeArea(
        child: favProducts.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.favorite_border_rounded,
                      size: 64,
                      color: AppColors.textSecondary.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Henüz favori ürününüz yok.',
                      style: AppTypography.titleMedium
                          .copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(AppSpacing.xl),
                itemCount: favProducts.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: AppSpacing.md),
                itemBuilder: (context, index) {
                  final product = favProducts[index];
                  return _FavoriteItemRow(product: product);
                },
              ),
      ),
    );
  }
}

class _FavoriteItemRow extends ConsumerWidget {
  final Map<String, String> product;

  const _FavoriteItemRow({required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productId = 'prod_${product['name'].hashCode}';
    final priceString = product['price']!.replaceAll(' TL', '');
    final double priceValue = double.tryParse(priceString) ?? 0.0;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.kMedium,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: const BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: AppRadius.kSmall,
            ),
            child: const Center(
              child: Icon(Icons.fastfood_outlined,
                  color: AppColors.primary, size: 32),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product['name']!,
                  style: AppTypography.titleMedium
                      .copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  product['desc']!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  product['price']!,
                  style: AppTypography.bodyLarge.copyWith(
                      fontWeight: FontWeight.bold, color: AppColors.primary),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Column(
            children: [
              IconButton(
                icon:
                    const Icon(Icons.favorite_rounded, color: Colors.redAccent),
                tooltip: 'Favorilerden çıkar',
                onPressed: () {
                  ref
                      .read(favoritesProvider.notifier)
                      .toggleFavorite(productId);
                },
              ),
              IconButton(
                icon: const Icon(Icons.add_shopping_cart_rounded,
                    color: AppColors.primary),
                tooltip: 'Sepete ekle',
                constraints: const BoxConstraints(
                  minWidth: AppThemeConstants.minTapTargetSize,
                  minHeight: AppThemeConstants.minTapTargetSize,
                ),
                onPressed: () {
                  ref.read(cartProvider.notifier).addToCart(
                        id: productId,
                        name: product['name']!,
                        desc: product['desc']!,
                        price: priceValue,
                      );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${product['name']} sepete eklendi.'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
