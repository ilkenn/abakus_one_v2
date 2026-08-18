import '../../../../core/errors/business_rule_violation.dart';
import '../../data/customer_photo_repository.dart';
import '../../domain/customer/customer_photo.dart';
import '../identity/customer_photo_id_generator.dart';

/// A customer submits a new photo for moderation — always starts
/// `pendingReview`. Throws [CustomerPhotoLimitReachedViolation] once the
/// customer already has [CustomerPhoto.maxEligiblePhotos] photos that
/// count toward the eligible limit (`CustomerPhoto.countsTowardEligible
/// Limit`). No authorization gate: this is the customer acting on their
/// own account, mirrors `SetCustomerCategory`'s self-service shape.
///
/// P.4.1 (2026-08-19): [organizationId] is now required and stamped onto
/// the created [CustomerPhoto] immutably — the tenant the photo was
/// submitted through, needed for the real `customerPhotos` Firestore
/// collection's tenant-isolation rule (`firestore.rules`). The 5-photo
/// limit this class enforced is now [CustomerPhoto.maxEligiblePhotos]
/// (10) — this client-side check remains a convenience/early-feedback
/// layer only; the eventual Cloud Function that actually performs the
/// write must re-enforce the same limit server-side (a modified client
/// could otherwise bypass this class entirely).
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
    required String organizationId,
    required String photoRef,
    required DateTime uploadedAt,
  }) async {
    final existing = await _repository.findByCustomerId(customerId);
    final eligibleCount =
        existing.where((p) => p.countsTowardEligibleLimit).length;
    if (eligibleCount >= CustomerPhoto.maxEligiblePhotos) {
      throw CustomerPhotoLimitReachedViolation(customerId: customerId);
    }

    final photo = CustomerPhoto(
      id: _idGenerator.nextPhotoId(),
      customerId: customerId,
      organizationId: organizationId,
      photoRef: photoRef,
      uploadedAt: uploadedAt,
      revision: 1,
    );
    await _repository.save(photo);
    return photo;
  }
}
