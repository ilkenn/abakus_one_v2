import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/admin_audit_entry_repository.dart';
import '../../data/customer_photo_repository.dart';
import '../../domain/audit/admin_audit_entry.dart';
import '../../domain/audit/admin_audit_event_type.dart';
import '../../../../shared/models/customer_photo.dart';
import '../../../../shared/models/customer_photo_status.dart';

/// The 4 core moderation actions from one use case — approve, reject,
/// remove, return-to-review — manager-authorized
/// (`PosAuthorizedAction.moderateCustomerPhoto`). Every action is
/// audited via [AdminAuditEntry]; "no hard deletion of moderation
/// history" holds because [remove] only changes [CustomerPhoto.status],
/// never deletes the record. Removing or rejecting a photo that was the
/// selected profile photo clears that selection — "deleting the profile
/// photo falls back to... default avatar" (falling back to *another*
/// approved photo is a separate, explicit customer/admin action —
/// [SelectCustomerProfilePhoto] — not auto-picked here, to avoid
/// silently choosing on the customer's behalf).
enum CustomerPhotoModerationAction { approve, reject, remove, returnToReview }

class ModerateCustomerPhoto {
  const ModerateCustomerPhoto({
    required PosAuthorizationPolicy authorizationPolicy,
    required CustomerPhotoRepository repository,
    required AdminAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _repository = repository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final CustomerPhotoRepository _repository;
  final AdminAuditEntryRepository _auditRepository;

  Future<CustomerPhoto> call({
    required String photoId,
    required CustomerPhotoModerationAction moderationAction,
    String? rejectionReason,
    required String performedByStaffId,
    required DateTime performedAt,
  }) async {
    const action = PosAuthorizedAction.moderateCustomerPhoto;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final existing = await _repository.findById(photoId);
    if (existing == null) {
      throw UnknownAdminEntityViolation(
          entityName: 'CustomerPhoto', id: photoId);
    }

    final newStatus = switch (moderationAction) {
      CustomerPhotoModerationAction.approve => CustomerPhotoStatus.approved,
      CustomerPhotoModerationAction.reject => CustomerPhotoStatus.rejected,
      CustomerPhotoModerationAction.remove => CustomerPhotoStatus.removed,
      CustomerPhotoModerationAction.returnToReview =>
        CustomerPhotoStatus.underReview,
    };
    final clearsSelection =
        moderationAction == CustomerPhotoModerationAction.reject ||
            moderationAction == CustomerPhotoModerationAction.remove;

    final updated = existing.copyWith(
      status: newStatus,
      isSelectedAsProfilePhoto:
          clearsSelection ? false : existing.isSelectedAsProfilePhoto,
      reviewedByStaffId: performedByStaffId,
      reviewedAt: performedAt,
      rejectionReason: moderationAction == CustomerPhotoModerationAction.reject
          ? rejectionReason
          : null,
      clearRejectionReason:
          moderationAction != CustomerPhotoModerationAction.reject,
      revision: existing.revision + 1,
    );
    await _repository.save(updated);

    await _auditRepository.appendEvent(AdminAuditEntry(
      id: '$photoId-audit-${performedAt.microsecondsSinceEpoch}',
      actorId: performedByStaffId,
      type: AdminAuditEventType.customerPhotoModerated,
      description: 'Customer photo ${moderationAction.name} '
          '(customer: ${existing.customerId})',
      targetEntityId: photoId,
      previousStateName: existing.status.name,
      newStateName: newStatus.name,
      timestamp: performedAt,
    ));

    return updated;
  }
}
