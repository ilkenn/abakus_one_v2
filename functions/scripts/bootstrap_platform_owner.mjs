// AP-2 Stage B — the ONE-TIME, out-of-band Platform Owner bootstrap
// mechanism (Correction #3, AP-2 Stage B approval). Deliberately NOT a
// Cloud Function / onCall endpoint: the very first Platform Owner has no
// existing Platform Owner to authorize them, so this step must happen
// outside the deployed app entirely, run manually by a trusted human
// operator who already holds real GCP project credentials (Application
// Default Credentials / a service account key) — that operator-credential
// requirement IS the actual trust boundary this script relies on, not
// anything invented in-app.
//
// Structurally self-limiting, not merely instructed to be careful:
//   - Refuses to run if ANY `platformMembers` document already has an
//     active `platformOwner` or `platformAdministrator` role. Every
//     subsequent Platform Owner/Administrator grant must go through the
//     real `grantPlatformRole` callable (itself Platform-Owner-authorized),
//     never this script again.
//   - Accepts Firebase Auth UIDs as a runtime argument — never a phone
//     number, email, or allowlist hardcoded into source.
//   - Writes a `platformBootstrapMarkers/{runId}` document and an
//     `auditEvents` entry recording that bootstrap ran, when, and for
//     which uids — so a later audit can see exactly one bootstrap
//     happened, never a silent second one.
//
// This is NOT a substitute for a real break-glass recovery plan if every
// Platform Owner account is ever lost — see `functions/README.md`'s
// "Platform Owner break-glass recovery" section for the GCP-IAM-based
// runbook (grant a trusted operator temporary `roles/datastore.user` via
// GCP IAM, run this script again — it becomes usable again ONLY because
// every existing platformMembers document has, by definition, no active
// owner/administrator role left, which is exactly the guard condition
// above, not a separate backdoor).
//
// Usage:
//   cd functions
//   node scripts/bootstrap_platform_owner.mjs <uid1> [uid2] [...]
//
// Requires GOOGLE_APPLICATION_CREDENTIALS (or another Application Default
// Credentials source) pointed at a real service account with Firestore +
// Auth Admin access for the target project, and GCLOUD_PROJECT (or
// --project) set to that project. Never run this against a project you do
// not intend to bootstrap — it is not reversible via this script itself.

import admin from "firebase-admin";

const PLATFORM_ROLE = "platformOwner";

function usageAndExit(message) {
  if (message) console.error(`[bootstrap_platform_owner] ${message}`);
  console.error(
    "[bootstrap_platform_owner] usage: node scripts/bootstrap_platform_owner.mjs <uid1> [uid2] [...]",
  );
  process.exit(1);
}

const uids = process.argv.slice(2).filter((arg) => arg.trim().length > 0);
if (uids.length === 0) {
  usageAndExit("at least one Firebase Auth uid is required.");
}
const uniqueUids = [...new Set(uids)];

const projectId = process.env.GCLOUD_PROJECT;
if (!projectId) {
  usageAndExit(
    "GCLOUD_PROJECT must be set to the real target project id — refusing to guess.",
  );
}

const app = admin.initializeApp({ projectId });
const db = admin.firestore();
const auth = admin.auth();

async function main() {
  console.log(`[bootstrap_platform_owner] target project: "${projectId}"`);
  console.log(`[bootstrap_platform_owner] target uids: ${uniqueUids.join(", ")}`);

  // Refuse to run if ANY active platformOwner/platformAdministrator already exists.
  const existingSnap = await db.collection("platformMembers").get();
  const existingActiveOwnerOrAdmin = existingSnap.docs.find((doc) => {
    const data = doc.data();
    return (
      data.status === "active" &&
      Array.isArray(data.roles) &&
      (data.roles.includes("platformOwner") || data.roles.includes("platformAdministrator"))
    );
  });
  if (existingActiveOwnerOrAdmin) {
    console.error(
      `[bootstrap_platform_owner] REFUSED: an active Platform Owner/Administrator already exists ` +
        `(platformMembers/${existingActiveOwnerOrAdmin.id}). Use the real grantPlatformRole callable ` +
        "for any further grant — this script only ever runs once per project.",
    );
    process.exit(1);
  }

  // Verify every uid is a real Firebase Auth account before writing anything.
  for (const uid of uniqueUids) {
    try {
      await auth.getUser(uid);
    } catch {
      console.error(`[bootstrap_platform_owner] REFUSED: no Firebase Auth account exists for uid "${uid}".`);
      process.exit(1);
    }
  }

  const now = admin.firestore.Timestamp.now();
  const runId = `bootstrap-${now.toMillis()}`;

  await db.runTransaction(async (tx) => {
    // Firestore transactions require every read to happen before any
    // write — reading all uids' current state up front (never
    // interleaving get()/set() per-uid in the same loop) before writing
    // any of them.
    const refs = uniqueUids.map((uid) => db.collection("platformMembers").doc(uid));
    const snaps = await Promise.all(refs.map((ref) => tx.get(ref)));

    uniqueUids.forEach((uid, index) => {
      const ref = refs[index];
      const snap = snaps[index];
      const existing = snap.exists ? snap.data() : null;
      const previousRoles = existing?.roles ?? [];
      const nextRoles = previousRoles.includes(PLATFORM_ROLE) ? previousRoles : [...previousRoles, PLATFORM_ROLE];
      const nextVersion = (existing?.version ?? 0) + 1;
      tx.set(ref, {
        displayName: existing?.displayName ?? uid,
        roles: nextRoles,
        status: "active",
        authUid: uid,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
        version: nextVersion,
      });
      tx.set(db.collection("auditEvents").doc(`${uid}-platform-bootstrap-${runId}`), {
        organizationId: null,
        branchId: null,
        type: "platform.bootstrapped",
        targetRef: ref.path,
        previousValue: previousRoles,
        newValue: nextRoles,
        actor: "system",
        actorType: "system",
        actorUid: null,
        actorRoles: null,
        reasonCode: "initial-platform-owner-bootstrap",
        reasonMessage: null,
        correlationId: runId,
        clientRequestId: null,
        timestamp: now.toDate().toISOString(),
      });
    });

    tx.set(db.collection("platformBootstrapMarkers").doc(runId), {
      runId,
      uids: uniqueUids,
      role: PLATFORM_ROLE,
      executedAt: now,
    });
  });

  console.log(
    `[bootstrap_platform_owner] done. ${uniqueUids.length} account(s) granted "${PLATFORM_ROLE}". ` +
      `Marker: platformBootstrapMarkers/${runId}. ` +
      "Each account must call syncOwnPlatformClaims and force a token refresh " +
      "(getIdToken(true)) before their platformRole claim takes effect.",
  );

  await app.delete();
}

main().catch((error) => {
  console.error("[bootstrap_platform_owner] failed:", error);
  process.exitCode = 1;
});
