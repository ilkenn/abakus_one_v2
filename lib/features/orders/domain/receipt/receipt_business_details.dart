/// Legal/business identification fields a printed receipt is expected to
/// carry — placeholders only. No real business registration data has been
/// supplied to this codebase; every field defaults to empty rather than a
/// fabricated value, so a receipt built without real data reads as
/// obviously incomplete instead of silently plausible.
class ReceiptBusinessDetails {
  const ReceiptBusinessDetails({
    this.legalBusinessName = '',
    this.taxOffice = '',
    this.taxRegistrationNumber = '',
    this.address = '',
  });

  final String legalBusinessName;

  /// Vergi dairesi.
  final String taxOffice;

  /// Vergi numarası.
  final String taxRegistrationNumber;

  final String address;
}
