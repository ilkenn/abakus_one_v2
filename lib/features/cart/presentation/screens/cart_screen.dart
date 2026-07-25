import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme_constants.dart';
import '../../../bowl_builder/data/bowl_builder_catalog.dart';
import '../../../bowl_builder/domain/models/bowl_builder_ingredient.dart';
import '../../../bowl_builder/presentation/providers/bowl_builder_provider.dart';
import '../../../bowl_builder/presentation/widgets/bowl_canvas.dart';
import '../../domain/models/cart_item.dart';
import '../providers/cart_provider.dart';
import 'checkout_screen.dart';

/// A custom bowl's cart line is the only kind of item Bowl Builder adds —
/// see `BowlBuilderScreen._addToCart`, which sets exactly this id prefix.
/// Reading it back here (display-only: which thumbnail to show) is the
/// smallest way to tell a custom-bowl row apart from a regular menu item's,
/// short of adding a new field to [CartItem] itself.
bool _isCustomBowl(CartItem item) => item.id.startsWith('custom_bowl_');

/// Reconstructs the distinct ingredients behind an already-placed bowl from
/// its frozen [CartItem.selectedModifiers] — a quantity-N ingredient
/// (Proteinler/Karbonhidratlar) produces N modifier entries with the same
/// `optionId`, so only the first occurrence of each id is kept; the bowl's
/// visual never multiplies by quantity, only its price does.
List<BowlBuilderIngredient> _bowlIngredientsFor(
  CartItem item,
  BowlBuilderCatalogRepository catalog,
) {
  final seenIds = <String>{};
  final result = <BowlBuilderIngredient>[];
  for (final modifier in item.selectedModifiers) {
    if (!seenIds.add(modifier.optionId)) continue;
    final ingredient = catalog.ingredientById(modifier.optionId);
    if (ingredient != null) result.add(ingredient);
  }
  return result;
}

class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cartItems = ref.watch(cartProvider);
    final totalPrice = ref.watch(cartTotalPriceProvider);
    final bowlCatalog = ref.watch(bowlBuilderCatalogRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sepetim'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: SafeArea(
        child: cartItems.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.shopping_basket_outlined,
                      size: 64,
                      color: AppColors.textSecondary.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Sepetiniz henüz boş.',
                      style: AppTypography.titleMedium
                          .copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              )
            : Column(
                children: [
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      itemCount: cartItems.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: AppSpacing.md),
                      itemBuilder: (context, index) {
                        final item = cartItems[index];
                        final isCustomBowl = _isCustomBowl(item);

                        return Container(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: AppRadius.kMedium,
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (isCustomBowl) ...[
                                SizedBox(
                                  width: 56,
                                  height: 56,
                                  child: ClipRRect(
                                    borderRadius: AppRadius.kMedium,
                                    child: ColoredBox(
                                      color: AppColors.surfaceVariant,
                                      child: BowlCanvas(
                                        ingredients: _bowlIngredientsFor(
                                          item,
                                          bowlCatalog,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.md),
                              ],
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.name,
                                      style: AppTypography.titleMedium.copyWith(
                                          fontWeight: FontWeight.bold),
                                    ),
                                    if (item.selectedProtein.isNotEmpty ||
                                        item.selectedSauce.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        '${item.selectedProtein.isNotEmpty ? item.selectedProtein : ""}${item.selectedProtein.isNotEmpty && item.selectedSauce.isNotEmpty ? " • " : ""}${item.selectedSauce.isNotEmpty ? item.selectedSauce : ""}',
                                        style: AppTypography.bodySmall.copyWith(
                                            color: AppColors.textSecondary),
                                      ),
                                    ],
                                    if (item.extraIngredients.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        '+ ${item.extraIngredients.join(", ")}',
                                        style: AppTypography.bodySmall.copyWith(
                                            color: AppColors.primary,
                                            fontWeight: FontWeight.w500),
                                      ),
                                    ],
                                    if (item.removedIngredients.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        '- ${item.removedIngredients.join(", ")}',
                                        style: AppTypography.bodySmall.copyWith(
                                            color: Colors.redAccent,
                                            fontStyle: FontStyle.italic),
                                      ),
                                    ],
                                    if (item.selectedModifiers.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        item.selectedModifiers
                                            .map((m) => m.optionName)
                                            .join(', '),
                                        style: AppTypography.bodySmall.copyWith(
                                            color: AppColors.textSecondary),
                                      ),
                                    ],
                                    if (item.note.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        'Not: ${item.note}',
                                        style: AppTypography.bodySmall.copyWith(
                                            color: AppColors.textSecondary,
                                            fontStyle: FontStyle.italic),
                                      ),
                                    ],
                                    const SizedBox(height: AppSpacing.sm),
                                    Text(
                                      '${item.totalRowPrice.toStringAsFixed(0)} TL',
                                      style: AppTypography.bodyLarge.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.primary),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  IconButton(
                                    icon: const Icon(
                                        Icons.delete_outline_rounded,
                                        color: Colors.redAccent,
                                        size: 20),
                                    tooltip: 'Sepetten kaldır',
                                    onPressed: () {
                                      ref
                                          .read(cartProvider.notifier)
                                          .removeFromCart(
                                              customizationsKey:
                                                  item.customizationsKey);
                                    },
                                    constraints: const BoxConstraints(
                                      minWidth:
                                          AppThemeConstants.minTapTargetSize,
                                      minHeight:
                                          AppThemeConstants.minTapTargetSize,
                                    ),
                                    padding: EdgeInsets.zero,
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                  Container(
                                    decoration: const BoxDecoration(
                                      color: AppColors.surfaceVariant,
                                      borderRadius: AppRadius.kSmall,
                                    ),
                                    child: Row(
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.remove_rounded,
                                              size: 16),
                                          tooltip: 'Adeti azalt',
                                          onPressed: () {
                                            ref
                                                .read(cartProvider.notifier)
                                                .decrementQuantity(
                                                    item.customizationsKey);
                                          },
                                          constraints: const BoxConstraints(
                                            minWidth: AppThemeConstants
                                                .minTapTargetSize,
                                            minHeight: AppThemeConstants
                                                .minTapTargetSize,
                                          ),
                                        ),
                                        Text(
                                          '${item.quantity}',
                                          style: AppTypography.bodyLarge
                                              .copyWith(
                                                  fontWeight: FontWeight.bold),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.add_rounded,
                                              size: 16),
                                          tooltip: 'Adeti artır',
                                          onPressed: () {
                                            ref
                                                .read(cartProvider.notifier)
                                                .incrementQuantity(
                                                    item.customizationsKey);
                                          },
                                          constraints: const BoxConstraints(
                                            minWidth: AppThemeConstants
                                                .minTapTargetSize,
                                            minHeight: AppThemeConstants
                                                .minTapTargetSize,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    decoration: const BoxDecoration(
                      color: AppColors.surface,
                      border: Border(top: BorderSide(color: AppColors.border)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Toplam Tutar',
                              style: AppTypography.titleMedium
                                  .copyWith(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              '${totalPrice.toStringAsFixed(0)} TL',
                              style: AppTypography.titleLarge.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (context) =>
                                        const CheckoutScreen()),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  vertical: AppSpacing.md),
                            ),
                            child: const Text('Siparişi Tamamla'),
                          ),
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
