/// ADR-085 (revision) — outcome of a staff phone + password sign-in.
/// [invalidCredentials] covers both "no such account" and "wrong
/// password": the sign-in screen never reveals whether a number is staff.
enum PasswordSignInResult { success, invalidCredentials, accountBlocked }

/// Outcome of a staff member changing their own password from the profile.
enum PasswordChangeResult { success, wrongCurrentPassword, weakPassword }
