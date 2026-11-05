import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Self-Order QR Faz 2 — the set of `MenuProduct.allergens` entries the
/// guest has chosen to avoid. A product containing any allergen in this set
/// is hidden from [MenuScreen]'s list (see that screen's `filteredProducts`)
/// — this is an exclusion filter, not a highlight: selecting "gluten" hides
/// every product that lists it, it never narrows the list down to show
/// *only* gluten-containing products.
class AllergenFilterNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void toggle(String allergen) {
    final next = Set<String>.from(state);
    if (!next.remove(allergen)) {
      next.add(allergen);
    }
    state = next;
  }

  void clear() => state = const {};
}

final allergenFilterProvider =
    NotifierProvider<AllergenFilterNotifier, Set<String>>(() {
  return AllergenFilterNotifier();
});
