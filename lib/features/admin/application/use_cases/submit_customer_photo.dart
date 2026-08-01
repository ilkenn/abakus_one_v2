import '../../../../core/errors/business_rule_violation.dart';
import '../../data/customer_photo_repository.dart';
import '../../domain/customer/customer_photo.dart';
import '../identity/customer_photo_id_generator.dart';

/// A customer submits a new photo for moderation — always starts
/// `pendingReview`. Throws [CustomerPhotoLimitReachedViolation] once the
/// customer already has 5 photos that count toward the eligible limit
/// (`CustomerPhoto.countsTowardEligibleLimit`) — "maximum 5 active/
/// eligible photos." No authorization gate: this is the customer acting
/// on their own account, mirrors `SetCustomerCategory`'s self-service
/// shape.
class SubmitCustomerPhoto {
  const SubmitCustomerPhoto({
    required CustomerPhotoIdGenerator idGenerator,
    required CustomerPhotoRepository repository,
  })  : _idGenerator = idGenerator,
        _repository = repository;

  final CustomerPhotoIdGenerator _idGenerator;
  final CustomerPhotoRepository _repository;

  Future<CustomerPhoto> call({
    required String customerId,
    required String photoRef,
    required DateTime uploadedAt,
  }) async {
    final existing = await _repository.findByCustomerId(customerId);
    final eligibleCount =
        existing.where((p) => p.countsTowardEligibleLimit).length;
    if (eligibleCount >= 5) {
      throw CustomerPhotoLimitReachedViolation(customerId: customerId);
    }

    final photo = CustomerPhoto(
      id: _idGenerator.nextPhotoId(),
      customerId: customerId,
      photoRef: photoRef,
      uploadedAt: uploadedAt,
      revision: 1,
    );
    await _repository.save(photo);
    return photo;
  }
}
