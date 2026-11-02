import '../domain/models/modifier_group.dart';
import '../domain/models/modifier_option.dart';

/// Shared, catalog-wide modifier-group definitions for the 2026-10-30
/// product-configurator rules (ingredient removal, Bowl carb/salad/pickle
/// rights, Burger/Wrap accompaniments, cross-sell). Defined once here and
/// applied to every relevant product in `AbakusMenuCatalog` rather than
/// duplicated per product literal — all ~38 Bowl/Burger/Wrap products
/// share the exact same groups/options/prices per the product owner's
/// explicit spec, so a single shared constant is the only place a price
/// change would ever need to be made.
///
/// Every price below is exactly as the product owner specified — none are
/// derived, guessed, or sourced from anywhere else.
abstract final class StandardModifierGroups {
  StandardModifierGroups._();

  /// Bowl's "ÇIKARILACAK STANDART MALZEMELER" — a universal, fixed list
  /// for every Bowl product (`cat_bowl2`), not derived from a per-product
  /// description (`cat_bowl2`'s products all have a bare "150g {Protein}."
  /// description with no ingredient breakdown to parse).
  ///
  /// 2026-10-30 correction (product owner): "Mor Lahana Turşusu" removed
  /// from this list — it was a duplicate of [bowlPickleGroup]'s own
  /// default option ("Turşu İstemiyorum" already covers removing it).
  /// The pickle choice lives *only* in [bowlPickleGroup] now.
  static const List<String> bowlRemovableIngredients = [
    'Mısır',
    'Susamlı Çörekotlu Salatalık',
  ];

  static const ModifierGroup bowlCarbGroup = ModifierGroup(
    id: 'bowl_carb',
    name: 'Karbonhidrat',
    selectionType: ModifierSelectionType.single,
    isRequired: true,
    minSelections: 1,
    maxSelections: 1,
    options: [
      ModifierOption(
          id: 'carb_basmati', name: 'Pirinç / Basmati Pilavı', isDefault: true),
      ModifierOption(id: 'carb_kuskus', name: 'Kuskus'),
      ModifierOption(id: 'carb_bulgur', name: 'Bulgur Pilavı'),
      ModifierOption(
          id: 'carb_meksika', name: 'Meksika Pilavı', extraPrice: 20),
      ModifierOption(
          id: 'carb_kremali_makarna', name: 'Kremalı Makarna', extraPrice: 20),
      ModifierOption(
          id: 'carb_kremali_pestolu_makarna',
          name: 'Kremalı Pestolu Makarna',
          extraPrice: 30),
      ModifierOption(
          id: 'carb_kremali_korili_makarna',
          name: 'Kremalı Körili Makarna',
          extraPrice: 30),
      ModifierOption(
          id: 'carb_kremali_kekikli_makarna',
          name: 'Kremalı Kekikli Makarna',
          extraPrice: 30),
      ModifierOption(id: 'carb_none', name: 'Karbonhidrat İstemiyorum'),
    ],
  );

  static const ModifierGroup bowlSaladGroup = ModifierGroup(
    id: 'bowl_salad',
    name: 'Salata',
    selectionType: ModifierSelectionType.single,
    isRequired: true,
    minSelections: 1,
    maxSelections: 1,
    options: [
      ModifierOption(
          id: 'salad_mevsim', name: 'Mevsim Salata', isDefault: true),
      ModifierOption(id: 'salad_marul', name: 'Marul'),
      ModifierOption(id: 'salad_roka', name: 'Roka'),
      ModifierOption(
          id: 'salad_roka_salata', name: 'Roka Salata', extraPrice: 40),
      ModifierOption(id: 'salad_coban', name: 'Çoban Salata', extraPrice: 40),
      ModifierOption(id: 'salad_none', name: 'Salata İstemiyorum'),
    ],
  );

  static const ModifierGroup bowlPickleGroup = ModifierGroup(
    id: 'bowl_pickle',
    name: 'Turşu',
    selectionType: ModifierSelectionType.single,
    isRequired: true,
    minSelections: 1,
    maxSelections: 1,
    options: [
      ModifierOption(
          id: 'pickle_mor_lahana', name: 'Mor Lahana Turşusu', isDefault: true),
      ModifierOption(
          id: 'pickle_kornison', name: 'Kornişon Turşu', extraPrice: 20),
      ModifierOption(
          id: 'pickle_jalapeno', name: 'Jalapeno Turşusu', extraPrice: 30),
      ModifierOption(id: 'pickle_kapari', name: 'Kapari', extraPrice: 40),
      ModifierOption(id: 'pickle_none', name: 'Turşu İstemiyorum'),
    ],
  );

  /// "SINIRSIZ PARALI EKSTRALAR" — optional, multi-select, no free option
  /// (every option here carries a price). `maxSelections` set to the
  /// option count so every option may be picked at once ("sınırsız" within
  /// this fixed list — there is no larger universe of extras to bound
  /// against).
  static const ModifierGroup bowlExtrasGroup = ModifierGroup(
    id: 'bowl_extras',
    name: 'Ekstra',
    selectionType: ModifierSelectionType.multiple,
    isRequired: false,
    minSelections: 0,
    maxSelections: 8,
    options: [
      ModifierOption(
          id: 'extra_salad_marul', name: 'Ekstra Marul', extraPrice: 40),
      ModifierOption(
          id: 'extra_salad_mevsim',
          name: 'Ekstra Mevsim Salata',
          extraPrice: 50),
      ModifierOption(
          id: 'extra_salad_roka', name: 'Ekstra Roka Salata', extraPrice: 70),
      ModifierOption(
          id: 'extra_salad_coban', name: 'Ekstra Çoban Salata', extraPrice: 80),
      ModifierOption(
          id: 'extra_carb_basmati',
          name: 'Ekstra Basmati Pilavı',
          extraPrice: 80),
      ModifierOption(
          id: 'extra_carb_meksika',
          name: 'Ekstra Meksika Pilavı',
          extraPrice: 100),
      ModifierOption(
          id: 'extra_carb_kremali_makarna',
          name: 'Ekstra Kremalı Makarna',
          extraPrice: 100),
      ModifierOption(
          id: 'extra_carb_kremali_pestolu_korili_kekikli',
          name: 'Ekstra Kremalı Pestolu/Körili/Kekikli Makarna',
          extraPrice: 120),
    ],
  );

  /// Every Bowl product (`cat_bowl2`) gets exactly these 4 groups, in this
  /// order — carb/salad/pickle (mandatory, in the order the bottom sheet
  /// renders them) then the optional paid extras last.
  static const List<ModifierGroup> bowlModifierGroups = [
    bowlCarbGroup,
    bowlSaladGroup,
    bowlPickleGroup,
    bowlExtrasGroup,
  ];

  /// Burger/Wrap "PATATES TERCİHİ" — mandatory single-select, every option
  /// free.
  static const ModifierGroup friesPreferenceGroup = ModifierGroup(
    id: 'fries_preference',
    name: 'Patates Tercihi',
    selectionType: ModifierSelectionType.single,
    isRequired: true,
    minSelections: 1,
    maxSelections: 1,
    options: [
      ModifierOption(
          id: 'fries_spicy',
          name: 'Baharatlı Patates Kızartması',
          isDefault: true),
      ModifierOption(id: 'fries_plain', name: 'Baharatsız Patates Kızartması'),
      ModifierOption(id: 'fries_none', name: 'Patates İstemiyorum'),
    ],
  );

  /// "KETÇAP & MAYONEZ TERCİHİ" — optional multi-select, both defaulted
  /// on (per spec: "Varsayılan seçili").
  static const ModifierGroup ketchupMayoGroup = ModifierGroup(
    id: 'ketchup_mayo',
    name: 'Ketçap & Mayonez',
    selectionType: ModifierSelectionType.multiple,
    isRequired: false,
    minSelections: 0,
    maxSelections: 2,
    options: [
      ModifierOption(
          id: 'sauce_ketchup', name: 'Ketçap İstiyorum', isDefault: true),
      ModifierOption(
          id: 'sauce_mayo', name: 'Mayonez İstiyorum', isDefault: true),
    ],
  );

  /// Every Burger/Wrap product (`cat_hamburger2`/`cat_wrap2`) gets exactly
  /// these 2 groups.
  static const List<ModifierGroup> burgerWrapModifierGroups = [
    friesPreferenceGroup,
    ketchupMayoGroup,
  ];

  /// "EKSTRA SOS ÖNERİSİ" — shown at the bottom of every product's
  /// selection modal/sheet (customer QR menu and POS staff entry alike),
  /// appended to every active product's own `modifierGroups` by
  /// `AbakusMenuCatalog.products` rather than duplicated per product.
  /// Optional multi-select; every option priced (no free sauce here).
  static const ModifierGroup crossSellSauceGroup = ModifierGroup(
    id: 'cross_sell_sauce',
    name: 'Ekstra Sos',
    selectionType: ModifierSelectionType.multiple,
    isRequired: false,
    minSelections: 0,
    maxSelections: 6,
    options: [
      ModifierOption(id: 'sauce_abakus', name: 'Abaküs Sos', extraPrice: 25),
      ModifierOption(
          id: 'sauce_balli_hardal', name: 'Ballı Hardal', extraPrice: 25),
      ModifierOption(id: 'sauce_barbeku', name: 'Barbekü', extraPrice: 20),
      ModifierOption(
          id: 'sauce_acili_mayonez', name: 'Acılı Mayonez', extraPrice: 25),
      ModifierOption(id: 'sauce_sriracha', name: 'Sriracha', extraPrice: 25),
      ModifierOption(
          id: 'sauce_trufflu_mayonez', name: 'Trüflü Mayonez', extraPrice: 30),
    ],
  );
}
