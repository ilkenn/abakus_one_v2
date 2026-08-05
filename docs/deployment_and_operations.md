# Backup, Deployment & CI/CD Foundation

Sprint 9J (`docs/decisions.md` ADR-026). Documentation-first, per the kickoff's own framing of this
sprint — "do not deploy production automatically without explicit release approval." Nothing in this
document has been executed against a real Firebase project during this phase; every claim below is
either a real, already-verified local/CI command, or explicitly marked as a documented procedure not
yet exercised.

## Environments

Three real, already-provisioned Firebase projects exist (`docs/decisions.md` ADR-026 Decision 1):

| Environment | Firebase project | Selected via |
|---|---|---|
| Development | `abakus-one-dev` | `AppEnvironment.development` (default) — connects to local emulators for Auth/Firestore/Storage/Functions |
| Staging | `abakus-one-staging` | `--dart-define=ENVIRONMENT=staging` |
| Production | `abakusone` | `--dart-define=ENVIRONMENT=production` |

`FirebaseOptionsSelector` (`lib/core/config/firebase_options_selector.dart`) resolves the right
project's `FirebaseOptions` via an exhaustive switch — an environment with no matching case is a
compile error, not a silent fallback to production.

## Secrets handling

- `firebase_options*.dart`, `google-services.json`, `GoogleService-Info.plist` — **not secrets**
  (standard FlutterFire client-config artifacts, already committed). CI's `forbidden-secrets-scan` job
  (`.github/workflows/ci.yml`, Sprint 9J) explicitly excludes these from its pattern match.
- Service-account JSON files and Cloud Functions runtime secrets (e.g. a future third-party API key) —
  **must never be committed**. None exist in this repository today (`functions/` has no
  `.env`/secret file — every function built this phase (9F/9G) uses only the Admin SDK's ambient
  credentials, which Cloud Functions' runtime provides automatically without a committed key).
- Real deployment would use `firebase functions:secrets:set` (Secret Manager-backed) for any future
  secret — not attempted this phase, since no function needs one yet.

## Firestore backup / point-in-time recovery — documented strategy, not yet enabled

No real Firestore data exists yet (greenfield). The documented approach for when real pilot data
exists:
- Enable [Firestore Point-in-Time Recovery](https://firebase.google.com/docs/firestore/pitr) on the
  production project before the pilot's first real customer order.
- A weekly scheduled export to Cloud Storage (`gcloud firestore export`) as a second, longer-retention
  backup layer, independent of PITR's shorter window.
- Tenant-aware restore: because every tenant document carries `organizationId` (Sprint 9B), a
  single-tenant restore is a Firestore export/import filtered by that field — not a full-database
  restore — but this procedure has not been tested against a real export.

## Storage backup / retention

No retention policy is configured on any Storage bucket yet. Documented intent: customer photos and
feedback attachments (`storage.rules`, Sprint 9H) should follow the same retention/anonymization
lifecycle as the CRM `Customer` record they're attached to (see `docs/decisions.md` ADR-026
Decision 8's account-deletion cascade) — not yet wired, since `processAccountDeletion` (9G) does not
reach into Storage today (named explicitly as a limitation in that sprint's own scope).

## Migration versioning & rollback

No schema-migration tooling exists (Firestore is schemaless; this app's own document shapes are
defined by the Dart mappers/TypeScript converters that write them, e.g. `OrderFirestoreMapper`,
Sprint 9E). A breaking document-shape change would need:
1. A dual-read period (new code reads both old and new shapes).
2. A backfill script (not built — no precedent exists in this codebase yet).
3. Removal of the old-shape read path only after backfill is confirmed complete.

This is documented intent, not a tested procedure — no document-shape migration has ever been
performed against real data in this project.

## Firestore Rules / Storage Rules / Functions deployment

Real, but **not yet run against a real project** this phase:
```
firebase deploy --only firestore:rules --project <alias>
firebase deploy --only storage --project <alias>
firebase deploy --only functions --project <alias>
```
`firebase.json` already wires `firestore.rules`/`storage.rules`/`functions/` (Sprints 9B/9H/9F) with a
`predeploy` build step for Functions (`npm --prefix functions run build`). No `.firebaserc` alias for
the three real projects has been added yet — only a `demo-` prefixed local-emulator-only project id
(`.firebaserc`, Sprint 9F) exists, deliberately, so no accidental real deploy target is ever configured
by default.

## Staged rollout / maintenance mode / incident response

- **Staged rollout**: not built. No canary/percentage-based rollout mechanism exists for either the
  Flutter app (store release percentages are a store-console concern, outside this codebase) or Cloud
  Functions (a single `onCall`/trigger deploy replaces the previous version entirely — no traffic
  splitting configured).
- **Maintenance mode**: foundation only (`MaintenanceModeStateRepository`, Phase 6O) — see
  `docs/observability_and_operations.md`'s "Not yet built" section; nothing currently reads this state
  to gate access.
- **Incident response**: no formal on-call rotation or paging integration exists (no real users yet).
  `docs/observability_and_operations.md`'s 8 runbook entries are the first-response foundation for
  when one is needed.

## CI/CD — what actually runs today

`.github/workflows/ci.yml`, extended this sprint with two new jobs alongside the existing `quality`
job (Phase 1, P1-004):

- **`emulator-tests`** — installs JDK 21 + Node 20 + `firebase-tools`, then runs the three
  emulator-backed suites this phase built: `firestore-tests/` (Sprint 9B, 22 tests),
  `storage-tests/` (Sprint 9H, 10 tests), and `functions/` (Sprints 9F/9G, 9 tests) — the exact same
  `firebase emulators:exec` commands already verified working locally throughout this phase, now also
  running in CI on every push/PR to `main`.
- **`forbidden-secrets-scan`** — a lightweight grep-based check for private-key/service-account
  patterns, excluding the known-safe FlutterFire client-config files.

**Honesty note**: these two CI jobs were written and are believed correct (they invoke the same
commands already proven to work locally in this session, with `actions/setup-java`/`actions/setup-node`
providing the same JDK 21 / Node 20 this session used via a portable local install) — but no GitHub
Actions run of this workflow has actually been observed to pass during this phase (no CI runner was
available in this session). Treat the `emulator-tests`/`forbidden-secrets-scan` jobs as "should work,
not yet confirmed working in the real CI environment," not as a verified-green pipeline.

**Not added to CI, deliberately deferred**: a "no release InMemory fallback" static check (would need
to trace every `Provider` in the app to confirm none resolves to an `InMemory*`/`NoOp*` implementation
in a release build — a genuinely useful but nontrivial static-analysis tool, not built this phase) and
a "no deterministic release OTP" check (already structurally impossible per Sprint 9C's
`firebaseReadyProvider`-gated `authRepositoryProvider` — `DevelopmentLocalAuthRepository` is never
constructed by any production provider — but no automated CI check *proves* this beyond the manual
code-review trail Sprint 9C's own commit already documents).
