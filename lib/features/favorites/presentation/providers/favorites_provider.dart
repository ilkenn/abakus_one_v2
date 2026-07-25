import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/favorite_item.dart';

class FavoritesState {
  final List<FavoriteItem> items;
  final List<CollectionModel> collections;

  const FavoritesState({required this.items, required this.collections});

  FavoritesState copyWith({
    List<FavoriteItem>? items,
    List<CollectionModel>? collections,
  }) {
    return FavoritesState(
      items: items ?? this.items,
      collections: collections ?? this.collections,
    );
  }
}

class FavoritesNotifier extends Notifier<FavoritesState> {
  @override
  FavoritesState build() {
    return const FavoritesState(
      items: [],
      collections: [
        CollectionModel(id: 'all', name: 'Tümü'),
        CollectionModel(id: 'col_1', name: 'Favori Bowllar'),
        CollectionModel(id: 'col_2', name: 'Sağlıklı Atıştırmalıklar'),
      ],
    );
  }

  void toggleFavorite(String productId) {
    final exists = state.items.any((item) => item.productId == productId);
    if (exists) {
      state = state.copyWith(
        items:
            state.items.where((item) => item.productId != productId).toList(),
      );
    } else {
      final newItem = FavoriteItem(
        productId: productId,
        addedAt: DateTime.now(),
        collectionIds: const ['all'],
      );
      state = state.copyWith(items: [...state.items, newItem]);
    }
  }

  void addCollection(String name) {
    final id = 'col_${DateTime.now().millisecondsSinceEpoch}';
    final newCollection = CollectionModel(id: id, name: name);
    state = state.copyWith(collections: [...state.collections, newCollection]);
  }

  void renameCollection(String id, String newName) {
    if (id == 'all') return;
    state = state.copyWith(
      collections: state.collections
          .map((c) => c.id == id ? c.copyWith(name: newName) : c)
          .toList(),
    );
  }

  void deleteCollection(String id) {
    if (id == 'all' || state.collections.length <= 1) return;
    state = state.copyWith(
      collections: state.collections.where((c) => c.id != id).toList(),
      items: state.items.map((item) {
        return item.copyWith(
          collectionIds: item.collectionIds.where((cId) => cId != id).toList(),
        );
      }).toList(),
    );
  }

  void updateProductCollections(String productId, List<String> collectionIds) {
    final updatedCollectionIds = collectionIds.contains('all')
        ? collectionIds
        : ['all', ...collectionIds];
    state = state.copyWith(
      items: state.items.map((item) {
        if (item.productId == productId) {
          return item.copyWith(collectionIds: updatedCollectionIds);
        }
        return item;
      }).toList(),
    );
  }
}

final favoritesProvider = NotifierProvider<FavoritesNotifier, FavoritesState>(
  () {
    return FavoritesNotifier();
  },
);
