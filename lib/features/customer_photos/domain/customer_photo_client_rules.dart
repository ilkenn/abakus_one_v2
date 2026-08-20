import '../../../shared/models/customer_photo.dart';
import '../../../shared/models/customer_photo_status.dart';

/// Profile P.4.3A — pure, client-side UX validation/presentation rules for
/// the customer photo upload flow. Backend/Storage remain the actual
/// authority (`storage.rules`' `isValidCustomerImageUpload()`,
/// `requestCustomerPhotoUploadGrant`'s own quota check) — everything here
/// exists only to give the user an honest, immediate signal before a
/// request round-trip, never as a substitute for server-side enforcement.

/// Mirrors `storage.rules`' `isValidCustomerImageUpload()` exactly
/// (`request.resource.size < 5 * 1024 * 1024`) — kept in sync by hand,
/// same disclosed limitation every other Dart/TypeScript-boundary
/// constant in this codebase already has (no single source of truth
/// reachable from both languages).
const int kMaxCustomerPhotoUploadBytes = 5 * 1024 * 1024;

/// CR.1.2 — the shared "is the customer's photo quota already full"
/// predicate, extracted once this became the 3rd call site to need it
/// (`CustomerPhotoManagementScreen`, `Step2PhotoStep` — the same "2nd
/// consumer promotes to a shared location" convention this codebase
/// already applies to whole files, applied here to a single predicate
/// instead of leaving a third inline copy). Server-authoritative quota
/// enforcement remains in `requestCustomerPhotoUploadGrant` regardless —
/// this only decides local UI affordance (hide/disable "Fotoğraf Ekle"),
/// never the real limit.
bool isCustomerPhotoQuotaFull(List<CustomerPhoto> photos) {
  final activeCount =
      photos.where((photo) => photo.countsTowardEligibleLimit).length;
  return activeCount >= CustomerPhoto.maxEligiblePhotos;
}

/// Resolves the content type to declare for an upload grant request and
/// to upload with. Prefers [mimeType] (what `XFile.mimeType` reports) —
/// reliable on Web (`image_picker_for_web` passes the browser File's own
/// `.type`), but `image_picker_android`/`image_picker_ios` never populate
/// it (confirmed by reading both plugins' source — neither ever
/// constructs an `XFile` with a `mimeType` argument), so on Android/iOS
/// this always falls through to [fileName]'s extension. This is "the
/// smallest reliable existing solution" for the ambiguous-MIME platforms,
/// not a claim that extension-sniffing is generally trustworthy — a
/// renamed file with a mismatched extension would still resolve wrong,
/// but `storage.rules`' own `contentType.matches('image/.*')` check is
/// the actual authority regardless of what this function guesses.
String? resolveCustomerPhotoContentType({
  required String? mimeType,
  required String fileName,
}) {
  if (mimeType != null && mimeType.isNotEmpty) return mimeType;

  final dotIndex = fileName.lastIndexOf('.');
  if (dotIndex == -1 || dotIndex == fileName.length - 1) return null;
  final extension = fileName.substring(dotIndex + 1).toLowerCase();
  const extensionToMimeType = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'heic': 'image/heic',
    'heif': 'image/heif',
    'webp': 'image/webp',
    'gif': 'image/gif',
  };
  return extensionToMimeType[extension];
}

/// Whether [contentType] is acceptable to even attempt an upload for —
/// mirrors `storage.rules`' own `contentType.matches('image/.*')` pattern
/// exactly (any `image/*`, not an enumerated whitelist) so this can never
/// reject something the backend would have accepted, or vice versa.
bool isSupportedCustomerPhotoContentType(String? contentType) {
  return contentType != null && contentType.startsWith('image/');
}

/// P.4.3B — which private/public presentation a resolved hero photo is in.
/// [pendingOwnerPrivate]/[underReviewOwnerPrivate] are visible ONLY to the
/// photo's own owner; [approvedSelected] mirrors what other users would
/// also see (the canonical public projection).
enum CustomerHeroPhotoPresentation {
  pendingOwnerPrivate,
  underReviewOwnerPrivate,
  approvedSelected,
}

/// The single photo (plus why) [ProfileHeroCard] should render for the
/// signed-in owner's own hero — never for any other viewer.
class ResolvedCustomerHeroPhoto {
  const ResolvedCustomerHeroPhoto({
    required this.photo,
    required this.presentation,
  });

  final CustomerPhoto photo;
  final CustomerHeroPhotoPresentation presentation;
}

/// P.4.3B — resolves which photo (if any) the customer's OWN Profile hero
/// should show, in locked priority order:
///
/// 1. The newest (by [CustomerPhoto.uploadedAt]) active `pendingReview`/
///    `underReview` photo — OWNER-PRIVATE ONLY, and deliberately allowed to
///    override an already-selected public photo (a customer who just
///    uploaded a replacement should see THAT one, not their old public
///    photo, while it's under moderation).
/// 2. Otherwise, the gallery photo whose [CustomerPhoto.photoRef] matches
///    [selectedProfilePhotoRef] **and** whose status is `approved` — this
///    is the canonical PUBLIC projection
///    (`customerPublicProfiles/{organizationId}_{uid}.selectedProfilePhotoRef`,
///    via `customerSelectedProfilePhotoRefProvider`), never
///    [CustomerPhoto.isSelectedAsProfilePhoto] read in isolation. That
///    per-photo field is a mirror, not the source of truth — re-deriving
///    "what's public" from it here would risk drifting from what other
///    users actually see if the two ever disagree.
/// 3. Otherwise `null` — the caller renders an initials avatar.
///
/// `rejected`/`removed` photos can never be returned — neither branch
/// above ever matches them (rejected/removed are excluded from the
/// pending/underReview set by definition, and the approved-only filter in
/// step 2 excludes them structurally too).
ResolvedCustomerHeroPhoto? resolveCustomerHeroPhoto({
  required List<CustomerPhoto> galleryPhotos,
  required String? selectedProfilePhotoRef,
}) {
  CustomerPhoto? newestPending;
  for (final photo in galleryPhotos) {
    final isPendingOrUnderReview =
        photo.status == CustomerPhotoStatus.pendingReview ||
            photo.status == CustomerPhotoStatus.underReview;
    if (!isPendingOrUnderReview) continue;
    if (newestPending == null ||
        photo.uploadedAt.isAfter(newestPending.uploadedAt)) {
      newestPending = photo;
    }
  }
  if (newestPending != null) {
    return ResolvedCustomerHeroPhoto(
      photo: newestPending,
      presentation: newestPending.status == CustomerPhotoStatus.pendingReview
          ? CustomerHeroPhotoPresentation.pendingOwnerPrivate
          : CustomerHeroPhotoPresentation.underReviewOwnerPrivate,
    );
  }

  if (selectedProfilePhotoRef != null) {
    for (final photo in galleryPhotos) {
      if (photo.photoRef == selectedProfilePhotoRef &&
          photo.status == CustomerPhotoStatus.approved) {
        return ResolvedCustomerHeroPhoto(
          photo: photo,
          presentation: CustomerHeroPhotoPresentation.approvedSelected,
        );
      }
    }
  }

  return null;
}

/// Customer-facing Turkish label for [status] — never staff/internal
/// terminology ("reviewer", "grant", "audit"), per the locked UX
/// requirement. `removed` uses plain "Kaldırıldı" rather than being
/// omitted — the photo is still shown to its own owner (structurally
/// permitted by `firestore.rules`' owner-read rule), it just no longer
/// counts toward the active-10 total.
String customerPhotoStatusLabel(CustomerPhotoStatus status) {
  switch (status) {
    case CustomerPhotoStatus.pendingReview:
      return 'Onay Bekliyor';
    case CustomerPhotoStatus.underReview:
      return 'İnceleniyor';
    case CustomerPhotoStatus.approved:
      return 'Onaylandı';
    case CustomerPhotoStatus.rejected:
      return 'Onaylanmadı';
    case CustomerPhotoStatus.removed:
      return 'Kaldırıldı';
  }
}
