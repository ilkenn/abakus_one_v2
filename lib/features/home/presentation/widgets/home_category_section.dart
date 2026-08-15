import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/config/asset_paths.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/images/editorial_asset_card.dart';
import '../../../menu/presentation/providers/menu_catalog_provider.dart';
import '../../../menu/presentation/providers/menu_filter_provider.dart';
import '../../../navigation/presentation/providers/navigation_provider.dart';

/// Horizontal editorial category cards — real artwork at its own 3:2
/// aspect ratio (never forced into a cropped square), sourced from the
/// real [menuCategoriesProvider], shown in the exact order below; tapping
/// filters Menu to that real category, same mechanism the old quick-
/// category chips already used.
class HomeCategorySection extends ConsumerWidget {
  const HomeCategorySection({super.key});

  static const double _cardWidth = 156;
  static const double _cardAspectRatio = 3 / 2;

  static const List<String> _visibleCategoryIds = [
    'cat_bowl',
    'cat_salata',
    'cat_wrap',
    'cat_hamburger',
    'cat_makarna',
    'cat_atistirmalik',
    'cat_icecekler',
  ];

  static const Map<String, IconData> _categoryIcons = {
    'cat_bowl': Icons.rice_bowl_rounded,
    'cat_salata': Icons.eco_rounded,
    'cat_wrap': Icons.fastfood_rounded,
    'cat_hamburger': Icons.lunch_dining_rounded,
    'cat_makarna': Icons.ramen_dining_rounded,
    'cat_atistirmalik': Icons.tapas_rounded,
    'cat_icecekler': Icons.local_drink_rounded,
  };

  static const Map<String, String> _categoryAssetFileNames = {
    'cat_bowl': 'bowl.webp',
    'cat_salata': 'salad.webp',
    'cat_wrap': 'wrap.webp',
    'cat_hamburger': 'burger.webp',
    'cat_makarna': 'pasta.webp',
    'cat_atistirmalik': 'snacks.webp',
    'cat_icecekler': 'drinks.webp',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allCategories = ref.watch(menuCategoriesProvider);
    final categoriesById = {for (final c in allCategories) c.id: c};
    final categories = [
      for (final id in _visibleCategoryIds)
        if (categoriesById[id] != null) categoriesById[id]!,
    ];
    if (categories.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Kategoriler',
            style: AppTypography.titleMedium.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 144,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: categories.length,
              itemBuilder: (context, index) {
                final category = categories[index];
                return Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.md),
                  child: SizedBox(
                    width: _cardWidth,
                    child: EditorialAssetCard(
                      assetPath: '${AssetPaths.homeCategoriesDirectory}'
                          '${_categoryAssetFileNames[category.id]}',
                      aspectRatio: _cardAspectRatio,
                      title: category.name,
                      placeholderIcon: _categoryIcons[category.id] ??
                          Icons.restaurant_rounded,
                      onTap: () {
                        ref
                            .read(menuFilterProvider.notifier)
                            .setFilter(category.name);
                        ref
                            .read(navigationProvider.notifier)
                            .selectTab(AppTab.menu);
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
