/// ADR-085 (revision) — the hidden sign-in e-mail of a staff account.
///
/// Firebase Auth has no phone + password provider, so a staff account
/// carries a technical e-mail derived from its phone number together with
/// the password. Nobody ever sees or types it: the staff member types the
/// phone number, the app derives this e-mail. It must stay identical to
/// `staffLoginEmailForPhone` in `functions/src/staffAccounts.ts`.
///
/// `+905551234567` → `905551234567@staff-login.abakus.invalid` (the
/// `.invalid` top-level domain can never receive mail, RFC 2606).
String staffLoginEmailForPhone(String normalizedPhoneNumber) {
  final digits = normalizedPhoneNumber.startsWith('+')
      ? normalizedPhoneNumber.substring(1)
      : normalizedPhoneNumber;
  return '$digits@staff-login.abakus.invalid';
}
