import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/images/product_image.dart';
import '../../../menu/domain/models/menu_product.dart';
import '../../../menu/presentation/providers/menu_catalog_provider.dart';
import '../../../menu/presentation/screens/product_detail_screen.dart';

/// "En Sevilen Bowl'lar" — horizontal, large-image-first product cards.
/// Only shows a tag when the product's own data actually supports one; as
/// of this task, [MenuProduct] only carries `isFeatured` (→ "Çok Satan") —
/// Vegan/Yüksek Protein/Yeni/Şefin Seçimi have no backing field yet, so
/// they simply never render rather than being guessed at.
class PopularProductsSection extends ConsumerWidget {
  const PopularProductsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(featuredMenuProductsProvider);
    if (products.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'En Sevilen Bowl\'lar',
            style: AppTypography.titleMedium.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 280,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: products.length,
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.only(right: AppSpacing.md),
                child: _PopularProductCard(product: products[index]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PopularProductCard extends StatelessWidget {
  final MenuProduct product;

  const _PopularProductCard({required this.product});

  @override
  Widget build(BuildContext context) {
    final tag = product.isFeatured ? 'Çok Satan' : null;

    return Semantics(
      button: true,
      label: '${product.name}, ${product.basePrice.toStringAsFixed(0)} TL'
          '${tag != null ? ', $tag' : ''}',
      child: Material(
        color: Colors.transparent,
        borderRadius: AppRadius.kLarge,
        child: InkWell(
          borderRadius: AppRadius.kLarge,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ProductDetailScreen(product: product),
            ),
          ),
          child: Container(
            width: 168,
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppRadius.kLarge,
              boxShadow: AppShadows.card,
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    ProductImage(
                      imageKey: product.imageKey,
                      width: 168,
                      height: 140,
                      borderRadius: BorderRadius.zero,
                      heroTag: 'home_product_image_${product.id}',
                    ),
                    if (tag != null)
                      Positioned(
                        left: AppSpacing.sm,
                        top: AppSpacing.sm,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: 2,
                          ),
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: AppRadius.kPill,
                          ),
                          child: Text(
                            tag,
                            style: AppTypography.caption.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        style: AppTypography.bodyLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${product.basePrice.toStringAsFixed(0)} TL',
                        style: AppTypography.priceMedium,
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
