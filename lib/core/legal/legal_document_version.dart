/// Current version identifiers for the Privacy Policy / Terms of Service —
/// Sprint 9G (`docs/decisions.md` ADR-026).
///
/// **DRAFT — LEGAL REVIEW REQUIRED.** No final legal text exists anywhere
/// in this codebase (`docs/phase9_architecture_analysis.md` §15 explicitly
/// scopes real legal content out of Phase 9 — "do not fabricate final
/// legal text"). These version identifiers exist only so the versioned-
/// acceptance *mechanism* (`NotificationSettingsModel.privacyPolicyAcceptedVersion`/
/// `termsAcceptedVersion`) is real and testable ahead of real content —
/// mirrors how `core/errors/error_mapper.dart` and other seams in this
/// app were built as tested contracts ahead of their eventual real
/// consumer. Bump these only when real, legally-reviewed content
/// replaces the current draft.
abstract final class LegalDocumentVersions {
  LegalDocumentVersions._();

  static const String privacyPolicy = 'draft-1';
  static const String terms = 'draft-1';
}
