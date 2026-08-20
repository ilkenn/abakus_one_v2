/// P.4.3B — how the canonical `customers/{uid}.occupationStatus` string
/// (set once at "Profilini Tamamla," CR.1) maps to a display-safe enum for
/// the Profile hero. Deliberately a NEW, independent enum — not imported
/// from `features/customer_registration/` (forbidden cross-feature
/// presentation import; even the domain-layer value here is kept local
/// rather than shared, since the two features read/write this concept for
/// different reasons and this hero-display enum needs no other consumer
/// today). [unknown] is the safe fallback for a missing/unrecognized raw
/// value — never invented, never thrown on.
enum CustomerOccupationStatus { working, student, other, unknown }

CustomerOccupationStatus parseCustomerOccupationStatus(String? raw) {
  switch (raw) {
    case 'working':
      return CustomerOccupationStatus.working;
    case 'student':
      return CustomerOccupationStatus.student;
    case 'other':
      return CustomerOccupationStatus.other;
    default:
      return CustomerOccupationStatus.unknown;
  }
}

/// P.4.3B — the customer's own canonical identity, read directly from
/// `customers/{uid}` (owner-only per `firestore.rules`, never another
/// customer's). Deliberately separate from `ProfileModel`/`profileProvider`
/// (which stay untouched — see `docs/decisions.md`'s P.4.3B entry) since
/// this represents real, persisted registration data, not the in-memory
/// auth-session bridge `ProfileModel` has always been.
class CustomerIdentity {
  const CustomerIdentity({
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.occupationStatus,
    this.workplaceName,
    this.educationalInstitutionName,
  });

  final String firstName;
  final String lastName;
  final String email;
  final CustomerOccupationStatus occupationStatus;
  final String? workplaceName;
  final String? educationalInstitutionName;

  /// `''` only if both names are empty — never throws, never fabricates a
  /// placeholder like "Ahmet Yılmaz."
  String get fullName => '$firstName $lastName'.trim();

  /// First letter of [firstName] + first letter of [lastName], e.g. "İP"
  /// for "İlken Parlakbudak" — `''` if both names are empty (the caller
  /// falls back to a generic person icon in that case, never a blank
  /// circle with invisible text).
  String get initials {
    final first = firstName.trim();
    final last = lastName.trim();
    final buffer = StringBuffer();
    if (first.isNotEmpty) buffer.write(first[0].toUpperCase());
    if (last.isNotEmpty) buffer.write(last[0].toUpperCase());
    return buffer.toString();
  }
}
