import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/qr_menu_theme.dart';
import '../../../../shared/widgets/images/product_image.dart';
import '../../../cart/presentation/providers/cart_provider.dart';
import '../../../cart/presentation/providers/shopping_channel_provider.dart';
import '../../domain/models/menu_product.dart';
import '../../domain/pricing/channel_pricing_policy.dart';
import '../providers/channel_price_display_provider.dart';
import '../providers/menu_catalog_provider.dart';
import '../screens/product_detail_screen.dart';

/// Instagram-Stories-style horizontal row of ring-bordered circular
/// thumbnails — "Warm Artisanal & Craft" QR-menu scope only. Sourced from
/// the real [featuredMenuProductsProvider] (the catalog's existing
/// `isFeatured` flag — "Çok Satanlar"/chef's-pick cross-listing), not a new
/// backend field or hardcoded content. Tapping a ring opens a focused
/// quick-view bottom sheet rather than any caption text on the strip
/// itself — avatars stay caption-free by design so this bar never
/// duplicates a product name already shown elsewhere on the same screen
/// (e.g. the product list directly below it); the name is still exposed to
/// assistive technology via [Semantics] and revealed visually once the
/// quick-view opens.
class QrMenuStoryBar extends ConsumerWidget {
  const QrMenuStoryBar({super.key});

  static const double _ringSize = 68;
  static const double _imageInset = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final featured = ref.watch(featuredMenuProductsProvider);
    if (featured.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: _ringSize + AppSpacing.sm,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        itemCount: featured.length,
        itemBuilder: (context, index) {
          final product = featured[index];
          return Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: _StoryRing(product: product),
          );
        },
      ),
    );
  }
}

class _StoryRing extends StatelessWidget {
  final MenuProduct product;

  const _StoryRing({required this.product});

  void _openQuickView(BuildContext context) {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _StoryQuickView(product: product),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${product.name}, öne çıkan ürün',
      child: GestureDetector(
        onTap: () => _openQuickView(context),
        child: Container(
          width: QrMenuStoryBar._ringSize,
          height: QrMenuStoryBar._ringSize,
          padding: const EdgeInsets.all(QrMenuStoryBar._imageInset),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [QrMenuColors.gold, QrMenuColors.terracotta],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: ClipOval(
            child: ProductImage(
              imageKey: product.imageKey,
              width: double.infinity,
              height: double.infinity,
              borderRadius: BorderRadius.zero,
              placeholderIconSize: 28,
            ),
          ),
        ),
      ),
    );
  }
}

class _StoryQuickView extends ConsumerWidget {
  final MenuProduct product;

  const _StoryQuickView({required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channelContext = ref.watch(shoppingChannelProvider);
    final policy =
        ref.watch(channelPricingPolicySnapshotProvider).valueOrNull ??
            const ChannelPricingPolicy();
    final price = resolveDisplayPrice(
      product: product,
      channelContext: channelContext,
      policy: policy,
    );
    final canQuickAdd = product.modifierGroups.isEmpty;

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(AppSpacing.md),
        decoration: const BoxDecoration(
          color: QrMenuColors.surface,
          borderRadius: AppRadius.kExtraLarge,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ProductImage(
              imageKey: product.imageKey,
              width: double.infinity,
              height: 200,
              borderRadius: BorderRadius.zero,
              placeholderIconSize: 64,
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.name, style: QrMenuTypography.title),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '${price.toStringAsFixed(0)} TL',
                    // `primary`, not `terracotta` — Verified: at 18px/w600
                    // this doesn't clear WCAG's large-text bar, and
                    // terracotta-on-white is only 4.23:1 (below the 4.5:1
                    // normal-text floor). `primary`-on-white is 12.30:1
                    // (see `qr_menu_theme.dart`'s contrast log).
                    style: QrMenuTypography.title.copyWith(
                      color: QrMenuColors.primary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    product.description,
                    style: QrMenuTypography.bodySecondary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: QrMenuColors.primary,
                            side: const BorderSide(color: QrMenuColors.primary),
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.md,
                            ),
                            shape: const RoundedRectangleBorder(
                              borderRadius: AppRadius.kMedium,
                            ),
                          ),
                          onPressed: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    ProductDetailScreen(product: product),
                              ),
                            );
                          },
                          child: const Text('Detayları Gör'),
                        ),
                      ),
                      if (canQuickAdd) ...[
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: QrMenuColors.primary,
                              foregroundColor: QrMenuColors.onPrimary,
                              padding: const EdgeInsets.symmetric(
                                vertical: AppSpacing.md,
                              ),
                              shape: const RoundedRectangleBorder(
                                borderRadius: AppRadius.kMedium,
                              ),
                            ),
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              ref.read(cartProvider.notifier).addToCart(
                                    id: product.id,
                                    name: product.name,
                                    desc: product.description,
                                    price: price,
                                    pricedForChannel: channelContext.channel,
                                  );
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content:
                                      Text('${product.name} sepete eklendi!'),
                                  duration: const Duration(seconds: 1),
                                ),
                              );
                            },
                            child: const Text('Sepete Ekle'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
