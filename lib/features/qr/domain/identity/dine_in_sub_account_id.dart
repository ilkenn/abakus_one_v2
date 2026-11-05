/// Mirrors `deterministicIdentitySubAccountId`
/// (`functions/src/tableSessionConfig.ts`) exactly — Self-Order QR Faz 3.
/// Used client-side only to compute the id a write must claim as its own
/// `addedBySubAccountId` (`firestore.rules`' own `dineInSubAccountIdFor`);
/// the server-side document itself (created by `openTableGuestSession`) is
/// always the real source of truth, this is never used to invent identity.
String deterministicIdentitySubAccountId({
  required String tableSessionId,
  required String uid,
}) {
  return 'subaccount-$tableSessionId-$uid';
}
