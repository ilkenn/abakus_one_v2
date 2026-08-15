import { onCall, HttpsError } from "firebase-functions/v2/https";
import {
  resolveTakeawayQrTokenInternal,
  toPublicPreview,
} from "./takeawayQrTokenResolution";
import { shouldEnforceAppCheck } from "./appCheckConfig";

/**
 * Read-only takeaway QR token preview — Faz D.2 (Gel Al QR + Guest
 * Session Backend). A public (unauthenticated-callable) HTTPS function —
 * mirrors `resolveTableQrToken`'s exact reasoning: a customer scanning a
 * kasadaki (register) QR hasn't signed in to anything yet at this point,
 * and this call never mutates state, so requiring auth here would gain
 * nothing security-wise while blocking the very first step of the flow.
 *
 * Deliberately never throws for an expected "this code doesn't work"
 * outcome (`notFound`/`invalid`/`expired`) — only a caller programming
 * error (missing/malformed `token`) throws.
 *
 * **Response is a [TakeawayQrPublicPreview], not the full internal
 * resolution**: no `organizationId`/`restaurantId`/`branchId` ever
 * leaves the server through this call. The canonical scope is
 * independently re-resolved, server-side, inside
 * `openTakeawayGuestSession`, which never accepts these ids as input
 * either — this response exists only to drive a confirmation UI, never
 * an authorization decision.
 *
 * **Abuse/rate-limit (Faz D.3 §15, closes Faz D.2's REQUIRED finding)**:
 * being public and unauthenticated, this endpoint is the one most exposed
 * to scripted abuse (token brute-forcing, scraping). `enforceAppCheck`
 * (`appCheckConfig.ts`'s `shouldEnforceAppCheck()`) is now wired — real
 * enforcement activates purely via a deployment environment variable
 * (`ENFORCE_APP_CHECK=true`) once a real App Check provider is
 * provisioned for the target project, no further code change needed; it
 * stays off in every emulator/local-dev run so this function's own test
 * suite is unaffected. `resolveTableQrToken` (the dine-in analogue) has
 * the exact same gap and was **not** touched this phase — flagged, not
 * silently left inconsistent, in this phase's own report. No custom
 * rate-limiter was built, per direct instruction not to build a
 * general-purpose rate-limit system here.
 */
export const resolveTakeawayQrToken = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request) => {
    const token = request.data?.token;
    if (typeof token !== "string" || token.length === 0) {
      throw new HttpsError("invalid-argument", "token is required.");
    }

    const resolution = await resolveTakeawayQrTokenInternal(token);
    return toPublicPreview(resolution);
  },
);
