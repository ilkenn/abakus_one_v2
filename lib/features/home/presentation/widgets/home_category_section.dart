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

  // 2026-10-28 PDF menu refresh — points at the new, active categories
  // (`AbakusMenuCatalog`'s own doc comment on `cat_bowl`/`cat_salata`/etc.
  // explains why the OLD 6 ids below are kept in the catalog, just
  // `isActive: false`, rather than deleted; this widget's own curated list
  // is independent of that flag, so it's updated here too — otherwise the
  // Home screen would keep advertising a menu customers can no longer see
  // in full on the Menu tab). `cat_icecekler` (İçecekler) is unchanged —
  // the PDF refresh never touched drinks.
  static const List<String> _visibleCategoryIds = [
    'cat_kahvalti',
    'cat_tartine',
    'cat_salata2',
    'cat_bowl2',
    'cat_tava',
    'cat_hamburger2',
    'cat_wrap2',
    'cat_makarna2',
    'cat_atistirmalik2',
    'cat_icecekler',
  ];

  static const Map<String, IconData> _categoryIcons = {
    'cat_kahvalti': Icons.egg_alt_rounded,
    'cat_tartine': Icons.bakery_dining_rounded,
    'cat_bowl2': Icons.rice_bowl_rounded,
    'cat_tava': Icons.outdoor_grill_rounded,
    'cat_salata2': Icons.eco_rounded,
    'cat_hamburger2': Icons.lunch_dining_rounded,
    'cat_wrap2': Icons.fastfood_rounded,
    'cat_makarna2': Icons.ramen_dining_rounded,
    'cat_atistirmalik2': Icons.tapas_rounded,
    'cat_icecekler': Icons.local_drink_rounded,
  };

  // Real artwork for the new categories doesn't exist yet — each resolves
  // to [_categoryIcons]' placeholder via [EditorialAssetCard]'s own
  // `errorBuilder` (same graceful fallback every other not-yet-shot
  // product/category image in this app already relies on), never a
  // broken image or a crash.
  static const Map<String, String> _categoryAssetFileNames = {
    'cat_kahvalti': 'breakfast.webp',
    'cat_tartine': 'tartine.webp',
    'cat_bowl2': 'bowl.webp',
    'cat_tava': 'tava.webp',
    'cat_salata2': 'salad.webp',
    'cat_hamburger2': 'burger.webp',
    'cat_wrap2': 'wrap.webp',
    'cat_makarna2': 'pasta.webp',
    'cat_atistirmalik2': 'snacks.webp',
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
