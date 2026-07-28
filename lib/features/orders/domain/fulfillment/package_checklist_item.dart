/// The category of one [PackageChecklistItem] on a [PackagePreparation].
enum PackageChecklistCategory {
  product,
  drink,
  sauce,
  cutlery,
  napkin,
  wetWipe,
  straw,
  dessert,
  campaignGift,
}

/// One item on a [PackagePreparation]'s completion checklist.
///
/// Deliberately flat and self-contained ([description] as text, not a
/// reference to a live product/campaign) — the same "snapshot, don't
/// reference" principle `OrderLine`/`OrderLineModifierSelection` already
/// follow, since a checklist reflects what this specific package needed
/// at packing time, not a live, later-editable catalog entry.
class PackageChecklistItem {
  const PackageChecklistItem({
    required this.category,
    required this.description,
    this.isChecked = false,
  });

  final PackageChecklistCategory category;
  final String description;
  final bool isChecked;

  PackageChecklistItem copyWith({bool? isChecked}) {
    return PackageChecklistItem(
      category: category,
      description: description,
      isChecked: isChecked ?? this.isChecked,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is PackageChecklistItem &&
            other.category == category &&
            other.description == description &&
            other.isChecked == isChecked);
  }

  @override
  int get hashCode => Object.hash(category, description, isChecked);
}
