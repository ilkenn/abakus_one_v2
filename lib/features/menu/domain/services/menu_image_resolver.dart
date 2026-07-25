import '../../../../core/config/asset_paths.dart';

/// Resolves a product's [imageKey] slug to an actual bundled asset path,
/// or `null` if no matching image exists yet.
///
/// This is the single place that knows which files exist under
/// `assets/images/menu/` — no screen or model ever builds an
/// `assets/images/menu/...` string itself. [_availableImageKeys] is kept in
/// sync with that directory's real contents; run the resolver's own test
/// suite after adding/removing image files to catch drift.
abstract final class MenuImageResolver {
  MenuImageResolver._();

  static const Set<String> _availableImageKeys = {
    'Vegan-Bowl',
    'abakus-burger',
    'abakus-shop',
    'akdeniz-salad',
    'ananas-salad',
    'asian-chicken-bowl',
    'asian-chicken-wrap',
    'asian-steak-wrap',
    'atom-bowl',
    'avokado-salad',
    'avokado-wrap',
    'beef-midye',
    'bonfile-bowl',
    'breakfast-bowl',
    'caesar-wrap',
    'cheese-burger',
    "chef's-fire-bowl",
    'citir-fettucine-chicken-alfredo',
    'citirti-bowl',
    'coban-salad',
    'crispy-caesar-salad',
    'crispy-chicken-wrap',
    'double-chicken-burger',
    'egg-wrap',
    'falafel-bowl',
    'falafel-burger',
    'falafel-salad',
    'fettucine-beef-alfredo',
    'fettucine-chicken-alfredo',
    'fettucine-crispy-chicken-alfredo',
    'fettucine-mushroom-alfredo',
    'gavurdagi-salad',
    'golden-harmony-bowl',
    'grill-caesar-salad',
    'grill-chicken-midye',
    'grill-chicken',
    'grill-salmon-bowl',
    'grill-salmon-salad',
    'grill-salmon-wrap',
    'gronola-bowl',
    'lokum-burger',
    'meatball-bowl',
    'meatball-fettucine',
    'meatball-midye',
    'meatball-salad',
    'meatball-wrap',
    'mexico-burger',
    'mexico-steak-wrap',
    'mexico-wrap',
    'mexifit-bowl',
    'mixed-bowl',
    'mixed-salad',
    "mom's-chicken-salad",
    'onion-burger',
    'rokato-salad',
    'smoke-house-burger',
    'smoke-salmon-bowl',
    'smoke-salmon-salad',
    'smoke-salmon-wrap',
    'steak-burger',
    'steak-salad',
    'steak-wrap',
    'sweet-sour-bowl',
    'swiss-mushrom-burger',
    'texas-steak-wrap',
    'tonton-bowl',
    'tonton-salad',
    'tonton-wrap',
    'tripoli-burger',
    'veggie-salad',
    'veggie-wrap',
  };

  /// The asset path for [imageKey], or `null` if it isn't one of the
  /// images actually bundled under `assets/images/menu/`. Callers must
  /// render a placeholder when this returns `null` — never guess a path.
  static String? resolve(String imageKey) {
    if (!_availableImageKeys.contains(imageKey)) return null;
    return '${AssetPaths.menuImageDirectory}$imageKey.png';
  }

  /// Every image key referenced by [products] that has no matching bundled
  /// asset. Intended for a one-off report (e.g. at catalog-load time in
  /// debug tooling), not for per-frame use.
  static List<String> findMissingImageKeys(Iterable<String> imageKeys) {
    return imageKeys
        .toSet()
        .where((key) => !_availableImageKeys.contains(key))
        .toList()
      ..sort();
  }
}
