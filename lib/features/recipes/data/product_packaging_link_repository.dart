import '../domain/product_packaging_link.dart';

abstract interface class ProductPackagingLinkRepository {
  Future<void> save(ProductPackagingLink link);
  Future<ProductPackagingLink?> findById(String id);

  /// The active link for [productId] on [channelCode], if any — `null`
  /// means this product/channel combination deliberately consumes no
  /// packaging stock (never an error).
  Future<ProductPackagingLink?> findByProductIdAndChannel(
    String productId,
    String channelCode,
  );
}

class InMemoryProductPackagingLinkRepository
    implements ProductPackagingLinkRepository {
  final Map<String, ProductPackagingLink> _byId = {};

  @override
  Future<void> save(ProductPackagingLink link) async => _byId[link.id] = link;

  @override
  Future<ProductPackagingLink?> findById(String id) async => _byId[id];

  @override
  Future<ProductPackagingLink?> findByProductIdAndChannel(
    String productId,
    String channelCode,
  ) async {
    for (final link in _byId.values) {
      if (link.productId == productId && link.channelCode == channelCode) {
        return link;
      }
    }
    return null;
  }
}
