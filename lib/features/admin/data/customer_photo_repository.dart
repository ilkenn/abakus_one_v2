import '../../../shared/models/customer_photo.dart';
import '../../../shared/models/customer_photo_status.dart';

abstract interface class CustomerPhotoRepository {
  Future<void> save(CustomerPhoto photo);
  Future<CustomerPhoto?> findById(String photoId);
  Future<List<CustomerPhoto>> findByCustomerId(String customerId);
  Future<List<CustomerPhoto>> findPendingReview();
}

class InMemoryCustomerPhotoRepository implements CustomerPhotoRepository {
  final Map<String, CustomerPhoto> _byId = {};

  @override
  Future<void> save(CustomerPhoto photo) async => _byId[photo.id] = photo;

  @override
  Future<CustomerPhoto?> findById(String photoId) async => _byId[photoId];

  @override
  Future<List<CustomerPhoto>> findByCustomerId(String customerId) async {
    return List.unmodifiable(
      _byId.values.where((p) => p.customerId == customerId),
    );
  }

  @override
  Future<List<CustomerPhoto>> findPendingReview() async {
    return List.unmodifiable(
      _byId.values.where((p) =>
          p.status == CustomerPhotoStatus.pendingReview ||
          p.status == CustomerPhotoStatus.underReview),
    );
  }
}
