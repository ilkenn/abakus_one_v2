import 'customer_photo_status.dart';

/// One customer-uploaded photo's moderation record — Phase 6G
/// (`docs/decisions.md` ADR-023). **[photoRef] is an opaque
/// storage-reference string, never raw media bytes** — "media bytes
/// must not be stored in audit logs... use metadata/storage-reference
/// contracts only unless secure media storage already exists" (none
/// does in this codebase — no `image_picker`/cloud-storage dependency
/// exists yet, confirmed during Phase 6's pre-implementation survey).
/// Mutable per-record status (mirrors `StaffMember`) — moderation
/// history itself is never hard-deleted; `removed` is a status, not a
/// row deletion.
///
/// P.4.1 (2026-08-19, Profile photo architecture prep): [organizationId]
/// added — every `CustomerPhoto` is scoped to the tenant it was
/// submitted through, mirroring `orders`/`tenantCustomers`'s existing
/// `organizationId` convention. It is **immutable after creation** (not
/// a `copyWith` parameter — see that method) and is the field the real
/// `customerPhotos` Firestore collection's tenant-isolation rule reads
/// (`firestore.rules`).
class CustomerPhoto {
  const CustomerPhoto({
    required this.id,
    required this.customerId,
    required this.organizationId,
    required this.photoRef,
    this.status = CustomerPhotoStatus.pendingReview,
    this.isSelectedAsProfilePhoto = false,
    required this.uploadedAt,
    this.reviewedByStaffId,
    this.reviewedAt,
    this.rejectionReason,
    required this.revision,
  });

  /// The customer's own maximum number of active/eligible photos at once
  /// — P.4.1 (2026-08-19): raised from 5 to 10, superseding every prior
  /// "max-5"/"maximum 5" reference in this codebase's docs/tests/comments.
  /// The single source of truth `SubmitCustomerPhoto` enforces against —
  /// no other file should hardcode this number again.
  static const int maxEligiblePhotos = 10;

  final String id;
  final String customerId;
  final String organizationId;
  final String photoRef;
  final CustomerPhotoStatus status;

  /// At most one of a customer's photos may have this `true`, and only
  /// if [status] is `approved` — enforced by `SelectCustomerProfilePhoto`,
  /// not by this constructor.
  final bool isSelectedAsProfilePhoto;

  final DateTime uploadedAt;
  final String? reviewedByStaffId;
  final DateTime? reviewedAt;
  final String? rejectionReason;
  final int revision;

  /// Whether this photo counts toward [maxEligiblePhotos] active/eligible
  /// photos — `rejected`/`removed` photos never consume the allowance.
  bool get countsTowardEligibleLimit =>
      status != CustomerPhotoStatus.rejected &&
      status != CustomerPhotoStatus.removed;

  CustomerPhoto copyWith({
    CustomerPhotoStatus? status,
    bool? isSelectedAsProfilePhoto,
    String? reviewedByStaffId,
    DateTime? reviewedAt,
    String? rejectionReason,
    bool clearRejectionReason = false,
    required int revision,
  }) {
    return CustomerPhoto(
      id: id,
      customerId: customerId,
      organizationId: organizationId,
      photoRef: photoRef,
      status: status ?? this.status,
      isSelectedAsProfilePhoto:
          isSelectedAsProfilePhoto ?? this.isSelectedAsProfilePhoto,
      uploadedAt: uploadedAt,
      reviewedByStaffId: reviewedByStaffId ?? this.reviewedByStaffId,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      rejectionReason: clearRejectionReason
          ? null
          : (rejectionReason ?? this.rejectionReason),
      revision: revision,
    );
  }
}
