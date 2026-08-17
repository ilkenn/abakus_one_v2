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
import 'home_section_title.dart';

/// "Abaküs'ün Favorileri" — H.2 rename/reframe of the former "En Sevilen
/// Bowl'lar" section. This is restaurant/editorial curation (Abaküs's own
/// picks), not a customer's personally-saved favorites list — same
/// [featuredMenuProductsProvider] real data source as before, only the
/// framing and card presentation changed, per the H.2 instruction to keep
/// the data source and redesign the cards to read as editorial rather than
/// generic-marketplace. Only shows a tag when the product's own data
/// actually supports one; as of this task, [MenuProduct] only carries
/// `isFeatured` (→ "Şefin Seçimi") — Vegan/Yüksek Protein/Yeni have no
/// backing field yet, so they simply never render rather than being
/// guessed at.
class PopularProductsSection extends ConsumerWidget {
  const PopularProductsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(featuredMenuProductsProvider);
    if (products.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const HomeSectionTitle('Abaküs\'ün Favorileri'),
        SizedBox(
          // H.2.1: shortened substantially from 292 — the extra height
          // wasn't image, it was unused white space below the price (a
          // horizontal ListView forces every card to this exact height,
          // and nothing below the text was filling it). The card's own
          // Expanded image now always fills whatever this leaves over
          // instead of leaving a gap, so this can stay compact without
          // reintroducing the earlier text-scale overflow.
          // H.2.2: tightened a further ~12% (220→194) — the text block
          // below the image was also tightened (see `_PopularProductCard`),
          // so the image's own share of this height grows, not just the
          // card's total shrinking.
          height: 194,
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
    );
  }
}

class _PopularProductCard extends StatelessWidget {
  final MenuProduct product;

  const _PopularProductCard({required this.product});

  @override
  Widget build(BuildContext context) {
    final tag = product.isFeatured ? 'Şefin Seçimi' : null;

    return Semantics(
      button: true,
      label: '${product.name}, ${product.basePrice.toStringAsFixed(0)} TL'
          '${tag != null ? ', $tag' : ''}',
      child: Material(
        color: Colors.transparent,
        borderRadius: AppRadius.kExtraLarge,
        child: InkWell(
          borderRadius: AppRadius.kExtraLarge,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ProductDetailScreen(product: product),
            ),
          ),
          child: Container(
            width: 176,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppRadius.kExtraLarge,
              border: Border.all(color: AppColors.border),
              boxShadow: AppShadows.card,
            ),
            clipBehavior: Clip.antiAlias,
            // Expanded image + a fixed-height text block — H.2.1: fills
            // the card's forced height (set by the horizontal ListView's
            // SizedBox) exactly, so there's never dead space below the
            // price no matter the exact text metrics at any text scale.
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ProductImage(
                        imageKey: product.imageKey,
                        width: 176,
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
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.surface.withValues(alpha: 0.92),
                              borderRadius: AppRadius.kPill,
                              boxShadow: AppShadows.subtle,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.eco_rounded,
                                  size: 12,
                                  color: AppColors.primary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  tag,
                                  style: AppTypography.caption.copyWith(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.xs,
                    AppSpacing.md,
                    AppSpacing.xs,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        // H.2.2: tighter line-height (1.2 vs bodyLarge's
                        // own 1.5) — same visible font size, denser box,
                        // so the image above gets a slightly larger share
                        // of the card's now-shorter total height.
                        style: AppTypography.bodyLarge.copyWith(
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${product.basePrice.toStringAsFixed(0)} TL',
                        style: AppTypography.priceMedium.copyWith(
                          color: AppColors.primary,
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
