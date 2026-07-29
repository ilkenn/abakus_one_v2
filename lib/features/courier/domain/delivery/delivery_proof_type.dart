/// How a delivery's completion was evidenced. [photoMetadata]/
/// [signatureMetadata] carry only metadata (a reference token, dimensions,
/// capture timestamp) — **never raw image/signature bytes**; no insecure
/// raw media storage exists in this phase (no secure blob storage
/// infrastructure exists in this codebase to store it safely in).
enum DeliveryProofType {
  courierConfirmation,
  customerConfirmationCode,
  signatureMetadata,
  photoMetadata,
  receptionNote,
  safePlaceNote,
  managerOverride,
}
