/// A minimal, deliberately narrow public-facing projection of one
/// customer's identity within one tenant — P.4.1 (2026-08-19, Profile
/// photo architecture prep). Modeled now so the real `customerPublicProfiles`
/// Firestore collection/rules and their tests have a concrete shape to
/// target; **no repository, use case, or provider is built yet** — this
/// is domain-shape prep only, not a wired feature (see `firestore.rules`
/// for the actual security boundary this shape backs).
///
/// Exists because Firestore has no field-level read permissions: the full
/// `customers/{uid}` document (email, deletion status, etc.) can never be
/// safely exposed to another customer or to staff outside the owning
/// tenant, but a future Community/Reviews-style feature needs *something*
/// publicly resolvable — so this is a separate, minimal document
/// containing only fields that are always safe for a same-tenant audience
/// to read, never the private CRM/customer record itself.
///
/// **Per-tenant, not global** — mirrors `tenantCustomers/{organizationId}
/// _{uid}`'s existing composite-key pattern (`docs/firestore_data_model
/// .md`) rather than a single global `customerPublicProfiles/{uid}`
/// document. A customer who interacts with more than one tenant gets one
/// projection per tenant, exactly like `tenantCustomers` already does —
/// this avoids inventing a new cross-tenant global-public read model,
/// which was explicitly out of scope for this phase.
///
/// [selectedProfilePhotoRef] is a nullable opaque storage-reference
/// string (never raw bytes, mirrors `CustomerPhoto.photoRef`) — `null`
/// until the customer has an `approved` photo actually selected. Only a
/// future `selectCustomerProfilePhoto` Cloud Function may ever write this
/// field; `firestore.rules`' `customerPublicProfiles` block denies every
/// client write unconditionally, so a pending/rejected/removed photo can
/// structurally never reach this document — there's no "later filter it
/// out" step to get wrong.
///
/// A public-safe display identity (name shown to other customers) is
/// deliberately NOT modeled here yet — no such concept exists anywhere
/// in this codebase today (`ProfileModel`/`customers/{uid}` have no
/// distinct "display name," only the account phone number/email), so
/// adding one now would be inventing product scope this phase wasn't
/// asked to decide.
class CustomerPublicProfile {
  const CustomerPublicProfile({
    required this.uid,
    required this.organizationId,
    this.selectedProfilePhotoRef,
    required this.updatedAt,
  });

  /// Same value as `CustomerPhoto.customerId` / `customers/{uid}`'s doc
  /// id — the real Firebase Auth uid, never a derived string.
  final String uid;

  /// The tenant this projection is scoped to — immutable after creation,
  /// same discipline as `CustomerPhoto.organizationId`.
  final String organizationId;

  /// Opaque ref to the customer's currently selected, `approved`
  /// `CustomerPhoto` — `null` when nothing is selected (falls back to a
  /// default placeholder avatar in the UI, never a broken image).
  final String? selectedProfilePhotoRef;

  final DateTime updatedAt;
}
