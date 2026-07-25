class FavoriteItem {
  final String productId;
  final DateTime addedAt;
  final List<String> collectionIds;

  const FavoriteItem({
    required this.productId,
    required this.addedAt,
    required this.collectionIds,
  });

  FavoriteItem copyWith({
    String? productId,
    DateTime? addedAt,
    List<String>? collectionIds,
  }) {
    return FavoriteItem(
      productId: productId ?? this.productId,
      addedAt: addedAt ?? this.addedAt,
      collectionIds: collectionIds ?? this.collectionIds,
    );
  }
}

class CollectionModel {
  final String id;
  final String name;

  const CollectionModel({required this.id, required this.name});

  CollectionModel copyWith({String? id, String? name}) {
    return CollectionModel(id: id ?? this.id, name: name ?? this.name);
  }
}
