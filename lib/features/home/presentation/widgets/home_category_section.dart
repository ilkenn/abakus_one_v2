import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/config/asset_paths.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/images/editorial_asset_card.dart';
import '../../../menu/presentation/providers/menu_catalog_provider.dart';
import '../../../menu/presentation/providers/menu_filter_provider.dart';
import '../../../navigation/presentation/providers/navigation_provider.dart';
import 'home_section_title.dart';

/// Horizontal editorial category cards — real artwork at its own 3:2
/// aspect ratio (never forced into a cropped square), sourced from the
/// real [menuCategoriesProvider], shown in the exact order below; tapping
/// filters Menu to that real category, same mechanism the old quick-
/// category chips already used.
///
/// H.1.1 — cards sized smaller/denser than order-mode cards (they're a
/// browsing shortcut, not a primary decision point) and the row height is
/// computed from that width/ratio rather than a hand-picked fixed number,
/// so it can never silently under-budget space for the shared
/// [EditorialAssetCard] chrome again (see `OrderModeSection`'s identical
/// pattern, established after H.1's phone-width overflow finding).
class HomeCategorySection extends ConsumerWidget {
  const HomeCategorySection({super.key});

  static const double _cardWidth = 128;
  static const double _cardAspectRatio = 3 / 2;
  // H.2.1: tightened from 48 — a single 14px label line doesn't need that
  // much reserved height; the extra space read as an oversized label area.
  // Kept at 42 rather than tighter still — anything below this overflows
  // the label at large accessibility text scales (1.6x), verified via the
  // Home accessibility regression test.
  static const double _textAreaHeight = 42;

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

    const imageHeight = _cardWidth / _cardAspectRatio;
    const rowHeight = imageHeight + _textAreaHeight;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const HomeSectionTitle('Kategoriler'),
        SizedBox(
          height: rowHeight,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final category = categories[index];
              return Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: SizedBox(
                  width: _cardWidth,
                  child: EditorialAssetCard(
                    assetPath: '${AssetPaths.homeCategoriesDirectory}'
                        '${_categoryAssetFileNames[category.id]}',
                    aspectRatio: _cardAspectRatio,
                    title: category.name,
                    placeholderIcon:
                        _categoryIcons[category.id] ?? Icons.restaurant_rounded,
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
    );
  }
}
