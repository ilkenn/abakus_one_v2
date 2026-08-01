import '../../../../core/errors/business_rule_violation.dart';
import '../../data/customer_photo_repository.dart';
import '../../domain/customer/customer_photo.dart';
import '../../domain/customer/customer_photo_status.dart';

/// Selects [photoId] as the customer's profile photo — "one approved
/// photo may be selected," "0 or 1 selected profile photo," "a selected
/// but unapproved photo must not become publicly visible" (enforced
/// structurally: throws [CustomerPhotoNotApprovedViolation] rather than
/// allowing it). Every other photo of the same customer is deselected
/// first, so the 0-or-1 invariant holds without a separate cleanup step.
/// No authorization gate — self-service, the customer's own choice.
class SelectCustomerProfilePhoto {
  const SelectCustomerProfilePhoto(
      {required CustomerPhotoRepository repository})
      : _repository = repository;

  final CustomerPhotoRepository _repository;

  Future<CustomerPhoto> call({required String photoId}) async {
    final photo = await _repository.findById(photoId);
    if (photo == null) {
      throw UnknownAdminEntityViolation(
          entityName: 'CustomerPhoto', id: photoId);
    }
    if (photo.status != CustomerPhotoStatus.approved) {
      throw CustomerPhotoNotApprovedViolation(photoId: photoId);
    }

    final siblings = await _repository.findByCustomerId(photo.customerId);
    for (final sibling in siblings) {
      if (sibling.id != photoId && sibling.isSelectedAsProfilePhoto) {
        await _repository.save(sibling.copyWith(
          isSelectedAsProfilePhoto: false,
          revision: sibling.revision + 1,
        ));
      }
    }

    final updated = photo.copyWith(
      isSelectedAsProfilePhoto: true,
      revision: photo.revision + 1,
    );
    await _repository.save(updated);
    return updated;
  }
}
