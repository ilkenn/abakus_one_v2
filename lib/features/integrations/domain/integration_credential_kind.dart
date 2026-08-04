/// The kind of secret an [IntegrationCredentialRef] points to — Phase 8
/// (`docs/decisions.md` ADR-025).
enum IntegrationCredentialKind {
  apiKey,
  oauthAccessToken,
  oauthRefreshToken,
  webhookSigningSecret,
}
