import { onCall, HttpsError } from "firebase-functions/v2/https";
import {
  resolveTableQrTokenInternal,
  toPublicPreview,
} from "./qrTokenResolution";
import { shouldEnforceAppCheck } from "./appCheckConfig";

/**
 * Read-only QR token preview — Table Guest Session Phase 2
 * (docs/decisions.md, Table Guest Session architecture). A public
 * (unauthenticated-callable) HTTPS function: a customer scanning a table
 * QR hasn't signed in to anything yet at this point, and this call never
 * mutates state, so requiring auth here would gain nothing security-wise
 * while blocking the very first step of the flow.
 *
 * Deliberately never throws for an expected "this code doesn't work"
 * outcome (`notFound`/`invalid`/`expired`) — mirrors
 * `TableQrResolutionResult.isUsable`'s own "never guess or fall back, but
 * also never treat an invalid scan as an exceptional error" contract.
 * Only a caller programming error (missing/malformed `token`) throws.
 *
 * **Response is a [TableQrPublicPreview], not the full internal
 * resolution**: no `organizationId`/`restaurantId`/`branchId`/`tableId`
 * ever leaves the server through this call (see that type's own doc
 * comment for why — data-minimization fix, this phase's review). The
 * canonical scope is independently re-resolved, server-side, inside
 * `openTableGuestSession`, which never accepts these ids as input either
 * — this response existing only to drive a confirmation UI, never an
 * authorization decision.
 *
 * **Abuse/rate-limit (Faz D.3.2 — closes the REQUIRED finding Faz D.3
 * reported: this function had the exact same public-endpoint exposure as
 * `resolveTakeawayQrToken` but was left unhardened)**: being public and
 * unauthenticated, this is the endpoint most exposed to scripted abuse
 * (token brute-forcing, scraping) — same reasoning as the takeaway
 * analogue. `enforceAppCheck` now reuses the exact same shared
 * `appCheckConfig.ts`'s `shouldEnforceAppCheck()` the takeaway functions
 * already use — not a second, parallel config system. Real enforcement
 * activates purely via the `ENFORCE_APP_CHECK=true` deployment
 * environment variable once a real App Check provider is provisioned for
 * the target project, no further code change needed; stays off in every
 * emulator/local-dev run, so this function's own existing test suite is
 * unaffected.
 */
export const resolveTableQrToken = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request) => {
    const token = request.data?.token;
    if (typeof token !== "string" || token.length === 0) {
      throw new HttpsError("invalid-argument", "token is required.");
    }

    const resolution = await resolveTableQrTokenInternal(token);
    return toPublicPreview(resolution);
  },
);
