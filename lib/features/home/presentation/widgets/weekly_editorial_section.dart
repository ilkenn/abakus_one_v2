import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/images/product_image.dart';
import '../../../menu/presentation/providers/menu_catalog_provider.dart';
import '../../../menu/presentation/screens/product_detail_screen.dart';
import 'home_section_title.dart';

/// "Bu Hafta Abaküs'te" — H.2.1 editorial redesign. One real product's own
/// real image/name/description/price from [featuredMenuProductsProvider]
/// (the same real data source the Favorites section above uses).
/// Deliberately picks the *last* featured product rather than the first,
/// so it doesn't visually echo the leading card of the Favorites row
/// directly above it.
///
/// H.2's first pass laid this out as a Row — image left, text right —
/// which read too much like an ordinary product-list item. H.2.1 instead
/// stacks a large full-width photo on top (the dominant element, an
/// asymmetric magazine-cover composition, not a side-by-side list row)
/// with a compact eyebrow/name/description block below it and the price
/// shown small and secondary, never competing with the product name.
///
/// No fabricated discount, popularity figure, or statistic is shown —
/// only the product's own `description` field, already part of the real
/// menu data model, as neutral supporting copy.
class WeeklyEditorialSection extends ConsumerWidget {
  const WeeklyEditorialSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(featuredMenuProductsProvider);
    if (products.isEmpty) return const SizedBox.shrink();
    final product = products.last;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const HomeSectionTitle('Bu Hafta Abaküs\'te'),
        Semantics(
          button: true,
          label: '${product.name}, bu haftanın seçimi, '
              '${product.basePrice.toStringAsFixed(0)} TL',
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
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: AppRadius.kExtraLarge,
                  border: Border.all(color: AppColors.border),
                  boxShadow: AppShadows.card,
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      children: [
                        AspectRatio(
                          aspectRatio: 16 / 9,
                          child: ProductImage(
                            imageKey: product.imageKey,
                            borderRadius: BorderRadius.zero,
                            heroTag: 'home_weekly_editorial_${product.id}',
                          ),
                        ),
                        Positioned(
                          left: AppSpacing.md,
                          top: AppSpacing.md,
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
                            child: Text(
                              'BU HAFTANIN SEÇİMİ',
                              style: AppTypography.caption.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
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
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            product.name,
                            style: AppTypography.titleLarge,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            product.description,
                            style: AppTypography.bodyMedium.copyWith(
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          // H.2.2: dropped even the w600 weight — plain
                          // regular-weight caption, as muted/secondary as
                          // this design system's smallest text role gets,
                          // deliberately never competing with the product
                          // name above it.
                          Text(
                            '${product.basePrice.toStringAsFixed(0)} TL',
                            style: AppTypography.caption,
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
      ],
    );
  }
}
