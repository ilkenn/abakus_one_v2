/// Customer Registration CR.1 — the customer's work/education status,
/// collected once during "Profilini Tamamla". Mirrors
/// `functions/src/completeCustomerProfile.ts`'s own `OCCUPATION_STATUSES`
/// string set exactly (`.name` is the wire value in both directions).
///
/// Personalization/segmentation data only — never an authorization input
/// (see `docs/decisions.md`'s Customer Registration CR.1 entry).
enum OccupationStatus { working, student, other }

/// Turkish, customer-facing label — "Çalışıyorum" / "Öğrenciyim" / "Diğer".
String occupationStatusLabel(OccupationStatus status) {
  switch (status) {
    case OccupationStatus.working:
      return 'Çalışıyorum';
    case OccupationStatus.student:
      return 'Öğrenciyim';
    case OccupationStatus.other:
      return 'Diğer';
  }
}
