/// A single selectable choice within a [ModifierGroup] (e.g. "Izgara Tavuk"
/// inside a "Protein" group, or "Avokado" inside an "Ekstra" group).
///
/// Reused as-is for Bowl Builder ingredients — a bowl ingredient (base,
/// protein, vegetable, extra, sauce) is architecturally the same concept as
/// a product modifier option, so Bowl Builder does not get its own
/// duplicate "ingredient" type.
class ModifierOption {
  final String id;
  final String name;
  final double extraPrice;
  final bool isDefault;
  final bool isAvailable;

  const ModifierOption({
    required this.id,
    required this.name,
    this.extraPrice = 0.0,
    this.isDefault = false,
    this.isAvailable = true,
  });

  ModifierOption copyWith({
    String? id,
    String? name,
    double? extraPrice,
    bool? isDefault,
    bool? isAvailable,
  }) {
    return ModifierOption(
      id: id ?? this.id,
      name: name ?? this.name,
      extraPrice: extraPrice ?? this.extraPrice,
      isDefault: isDefault ?? this.isDefault,
      isAvailable: isAvailable ?? this.isAvailable,
    );
  }
}
