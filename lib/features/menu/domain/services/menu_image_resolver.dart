import '../../../../core/config/asset_paths.dart';

/// Resolves a product's [imageKey] (plus its `MenuCategory.id`) to every
/// bundled asset path worth trying, in order — no screen or model ever
/// builds an `assets/images/menu/...` string itself.
///
/// Real photos live under `assets/images/menu/<categorySlug>/`, one
/// subfolder per active `MenuCategory.id` with its `cat_` prefix and any
/// trailing product-refresh "2" suffix stripped (e.g. `cat_wrap2` →
/// `wrap/`, `cat_kahvalti` → `kahvalti/`).
///
/// **2026-11-02 — corrected after an audit against the real catalog and
/// the real files on disk.** The catalog's own `imageKey` values don't
/// reliably start with the folder slug: several categories keep their
/// product-refresh "2" in the key itself (`salata2-veggie`, `wrap2-
/// asian-chicken`, `bowl2-tatli-eksi-tavuk`), and one uses a wholly
/// different word than its folder (`atistirmalik2`'s keys all start with
/// `aperatif-`, not `atistirmalik-`). Stripping by the *folder* slug
/// therefore silently never matched for any of those — this resolver now
/// strips by the key's own first hyphen-delimited segment instead,
/// whatever it actually is, which handles every category uniformly
/// without a second, hand-authored "real prefix per category" table.
/// Also tries that stripped stem with the folder slug appended as a
/// *suffix* (`bowl/tatli-eksi-tavuk-bowl.png`, `wrap/asian-chicken-
/// wrap.png`) — the convention several categories' real files actually
/// use — and both `.png` and `.jpg` (`atistirmalik/`, `makarna/` are
/// `.jpg`). [ProductImage]'s own chained `errorBuilder` is what falls
/// back to a placeholder for a candidate that doesn't exist yet; this
/// never maintains a "which files exist" allowlist.
///
/// **Known limitation, deliberately not special-cased**: a category
/// whose products share a common second word (e.g. `icecekler`'s
/// `acili-ayran`/`naneli-ayran`/`eksili-ayran`/`feslegenli-ayran`, all
/// stripping to `ayran`) could, in principle, collide on a shared
/// stripped-stem file like `ayran.png` if one were ever added — naming
/// such a file by its full `imageKey` instead (tried first, always)
/// avoids this.
///
/// **One disclosed exception**: `hamburger/`'s real files use `-burger`
/// as their suffix word (`double-chicken-burger.png`), not `-hamburger`
/// — the one category where the folder slug and the word its own real
/// files use genuinely differ (a Turkish colloquialism, not derivable
/// from `MenuCategory.id`/the folder name by any string rule). Rather
/// than rename all 13 files, [_suffixAlias] names this single, explicit
/// exception — intentionally not a general "real word per category"
/// table, just the one case that needs it.
abstract final class MenuImageResolver {
  MenuImageResolver._();

  static const List<String> _extensions = ['png', 'jpg'];

  static const Map<String, String> _suffixAlias = {'hamburger': 'burger'};

  /// Every candidate asset path for [imageKey], in try-order — empty if
  /// [categoryId] isn't a real `cat_`-prefixed id. Callers render a
  /// placeholder once every candidate here has failed to load — never
  /// guess a path beyond what this returns.
  static List<String> resolveCandidates(String imageKey, {String? categoryId}) {
    if (categoryId == null || !categoryId.startsWith('cat_')) return const [];

    final categorySlug = _categorySlug(categoryId);
    final folder = '${AssetPaths.menuImageDirectory}$categorySlug/';
    final alias = _suffixAlias[categorySlug];
    final suffixWords = alias == null ? [categorySlug] : [categorySlug, alias];

    final stems = <String>[imageKey];
    final firstHyphen = imageKey.indexOf('-');
    if (firstHyphen > 0) {
      final tail = imageKey.substring(firstHyphen + 1);
      if (tail.isNotEmpty) {
        stems.add(tail);
        for (final suffixWord in suffixWords) {
          stems.add('$tail-$suffixWord');
        }
      }
    }

    return [
      for (final stem in stems)
        for (final ext in _extensions) '$folder$stem.$ext',
    ];
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
