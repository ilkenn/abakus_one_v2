/// The 14 EU-regulation-style allergen categories plus [other] — Phase
/// 7 (`docs/decisions.md` ADR-024). A fixed enum today, not yet a
/// per-country-configurable catalog — the brief's "country-
/// configurable catalog" is deferred generalization work; building a
/// full admin-configurable catalog now would be speculative scope
/// beyond what's proportionate this phase, so this enum is the
/// honestly-scoped default catalog instead.
enum AllergenType {
  gluten,
  milk,
  egg,
  peanut,
  treeNuts,
  sesame,
  soy,
  fish,
  crustaceans,
  molluscs,
  mustard,
  celery,
  sulphites,
  lupin,
  other,
}
