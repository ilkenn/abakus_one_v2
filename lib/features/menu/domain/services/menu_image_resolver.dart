import '../../../../core/config/asset_paths.dart';

/// Resolves a product's [imageKey] (plus its `MenuCategory.id`) to every
/// bundled asset path worth trying, in order — no screen or model ever
/// builds an `assets/images/menu/...` string itself.
///
/// **2026-11-02 — per-category convention.** Real photos live under
/// `assets/images/menu/<categorySlug>/`, one subfolder per active
/// `MenuCategory.id` with its `cat_` prefix and any trailing
/// product-refresh "2" suffix stripped (e.g. `cat_wrap2` → `wrap/`,
/// `cat_kahvalti` → `kahvalti/`). Within a category folder, a file is
/// named either the full [imageKey] (e.g. `atistirmalik/general-tso.png`
/// for imageKey `general-tso`) or the [imageKey] with that same category
/// slug's own `-` prefix stripped (e.g. `kahvalti/clasico.png` for
/// imageKey `kahvalti-clasico`) — both are tried, since both are real,
/// already-in-use conventions. This never maintains a "which files
/// exist" allowlist: [ProductImage]'s own chained `errorBuilder` is what
/// falls back to a placeholder for a candidate that doesn't exist yet.
abstract final class MenuImageResolver {
  MenuImageResolver._();

  /// Every candidate asset path for [imageKey], in try-order — empty if
  /// [categoryId] isn't a real `cat_`-prefixed id. Callers render a
  /// placeholder once every candidate here has failed to load — never
  /// guess a path beyond what this returns.
  static List<String> resolveCandidates(String imageKey, {String? categoryId}) {
    if (categoryId == null || !categoryId.startsWith('cat_')) return const [];

    final categorySlug = _categorySlug(categoryId);
    final folder = '${AssetPaths.menuImageDirectory}$categorySlug/';
    final candidates = <String>['$folder$imageKey.png'];

    final prefix = '$categorySlug-';
    if (imageKey.startsWith(prefix)) {
      final stripped = imageKey.substring(prefix.length);
      candidates.add('$folder$stripped.png');
    }
    return candidates;
  }

  /// `cat_wrap2` → `wrap`, `cat_kahvalti` → `kahvalti`. The trailing "2"
  /// only ever marks a product-refresh revision of an existing category
  /// (e.g. `cat_wrap` → `cat_wrap2`); the photo folder name was already
  /// chosen without it, so stripping it here avoids a second,
  /// hand-authored slug list drifting out of sync with the catalog.
  static String _categorySlug(String categoryId) {
    final withoutPrefix = categoryId.substring('cat_'.length);
    return withoutPrefix.endsWith('2')
        ? withoutPrefix.substring(0, withoutPrefix.length - 1)
        : withoutPrefix;
  }
}
