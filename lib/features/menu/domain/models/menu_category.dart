/// A top-level grouping of products on the menu (e.g. "Bowl", "Salata").
class MenuCategory {
  final String id;
  final String name;
  final int sortOrder;
  final bool isActive;

  const MenuCategory({
    required this.id,
    required this.name,
    required this.sortOrder,
    required this.isActive,
  });

  MenuCategory copyWith({
    String? id,
    String? name,
    int? sortOrder,
    bool? isActive,
  }) {
    return MenuCategory(
      id: id ?? this.id,
      name: name ?? this.name,
      sortOrder: sortOrder ?? this.sortOrder,
      isActive: isActive ?? this.isActive,
    );
  }
}
