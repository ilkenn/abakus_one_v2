import { randomUUID } from "node:crypto";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import { getFirestore } from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import {
  defaultAutocompleteFn,
  defaultPlaceDetailsFn,
  type AutocompleteFn,
  type PlaceDetailsFn,
} from "./googlePlacesClient";
import { defaultReverseGeocodeFn, type ReverseGeocodeFn } from "./googleGeocodingClient";
import { normalizePlaceDetails, isSufficientlyResolved } from "./googlePlacesFieldMapping";
import { parseDeviceLocationCandidate } from "./fraud/deviceLocationCandidate";
import { distanceMeters } from "./fraud/geoDistance";
import {
  createFraudEvidenceInTransaction,
  FRAUD_F1_POLICY_VERSION,
} from "./fraud/fraudEvidenceRepository";
import type { ServerFraudInterpretation } from "./fraud/fraudEvidenceTypes";

/**
 * Faz P.2 — Google Places API (New) address foundation. Three callables:
 *
 * - [searchAddressAutocomplete]: read-only, returns suggestions.
 * - [resolveAddressPlace]: read-only, resolves one placeId to a preview
 *   (§3's "resolve canonical address components → show resolved address"
 *   step, before the customer fills in apartment/floor/description).
 * - [saveDeliveryAddress]: the only write path. **Independently
 *   re-resolves the given placeId server-side** (§5 — "server must
 *   independently resolve/verify the selected provider identity"), never
 *   trusting anything [resolveAddressPlace] returned moments earlier to
 *   the same client, and never any client-supplied address component.
 *
 * Only one Google credential is provisioned for this app
 * (`GOOGLE_PLACES_SERVER_KEY`, a Secret Manager secret, restricted to
 * Places API (New) only) — no client-side key exists. All three
 * callables therefore run server-side; there is no direct client→Google
 * network path. This is a disclosed architecture choice, not an
 * oversight: a future phase could add a client-restricted key purely to
 * shave autocomplete latency, at the cost of a second credential to
 * manage — not done here since it wasn't provisioned and isn't required
 * for correctness (`docs/decisions.md` Faz P.2).
 */

export const googlePlacesServerKey = defineSecret("GOOGLE_PLACES_SERVER_KEY");

function isEmulatorContext(): boolean {
  return Boolean(process.env.FIRESTORE_EMULATOR_HOST || process.env.FUNCTIONS_EMULATOR);
}

/**
 * Never reads the real Secret Manager value in emulator context — the
 * `default*Fn()` factories in `googlePlacesClient.ts` already short-circuit
 * to a fake that ignores whatever this returns, but this guard means an
 * emulator run can never even attempt a real Secret Manager read (which
 * would fail anyway against the demo emulator project) as an extra layer,
 * not the only one.
 */
function resolveApiKey(): string {
  return isEmulatorContext() ? "emulator-unused" : googlePlacesServerKey.value();
}

interface AutocompleteResult {
  suggestions: { placeId: string; text: string }[];
}

export const searchAddressAutocomplete = onCall(
  { secrets: [googlePlacesServerKey], enforceAppCheck: shouldEnforceAppCheck() },
  async (request): Promise<AutocompleteResult> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in is required.");
    }
    const input = request.data?.input;
    const sessionToken = request.data?.sessionToken;
    if (typeof sessionToken !== "string" || sessionToken.length === 0) {
      throw new HttpsError("invalid-argument", "sessionToken is required.");
    }
    if (typeof input !== "string" || input.trim().length === 0) {
      // Faz P.2 §12 — never send a request for empty/meaningless input.
      return { suggestions: [] };
    }

    const fn: AutocompleteFn = defaultAutocompleteFn();
    const suggestions = await fn(resolveApiKey(), input, sessionToken);
    return { suggestions };
  },
);

interface ResolveAddressResult {
  resolved: {
    providerPlaceId: string;
    formattedAddress: string | null;
    provinceName: string | null;
    districtName: string | null;
    neighborhoodName: string | null;
    routeName: string | null;
    streetNumber: string | null;
    latitude: number | null;
    longitude: number | null;
  };
  sufficientlyResolved: boolean;
}

export const resolveAddressPlace = onCall(
  { secrets: [googlePlacesServerKey], enforceAppCheck: shouldEnforceAppCheck() },
  async (request): Promise<ResolveAddressResult> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in is required.");
    }
    const placeId = request.data?.placeId;
    const sessionToken = request.data?.sessionToken;
    if (typeof placeId !== "string" || placeId.length === 0) {
      throw new HttpsError("invalid-argument", "placeId is required.");
    }
    if (typeof sessionToken !== "string" || sessionToken.length === 0) {
      throw new HttpsError("invalid-argument", "sessionToken is required.");
    }

    const fn: PlaceDetailsFn = defaultPlaceDetailsFn();
    const raw = await fn(resolveApiKey(), placeId, sessionToken);
    if (!raw) {
      throw new HttpsError("not-found", "Unknown or unresolvable place id.");
    }
    const normalized = normalizePlaceDetails(placeId, raw);
    return { resolved: normalized, sufficientlyResolved: isSufficientlyResolved(normalized) };
  },
);

interface SaveDeliveryAddressResult {
  addressId: string;
  verificationStatus: "verified" | "unverified";
}

export const saveDeliveryAddress = onCall(
  { secrets: [googlePlacesServerKey], enforceAppCheck: shouldEnforceAppCheck() },
  async (request): Promise<SaveDeliveryAddressResult> => {
    // FRAUD-F.1 — captured before any other work, so it genuinely reflects
    // when this authoritative request arrived (docs/fraud_evidence_architecture.md).
    const serverReceivedAt = new Date().toISOString();

    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in is required.");
    }
    const uid = request.auth.uid;
    const data = request.data ?? {};

    const placeId = data.placeId;
    if (typeof placeId !== "string" || placeId.length === 0) {
      throw new HttpsError("invalid-argument", "placeId is required.");
    }
    const label = data.label;
    if (typeof label !== "string" || label.trim().length === 0) {
      throw new HttpsError("invalid-argument", "label is required.");
    }
    const apartmentNo = data.apartmentNo;
    if (typeof apartmentNo !== "string" || apartmentNo.trim().length === 0) {
      // Faz P.2 §6 — apartment number is always customer input; never
      // optional, never provider-sourced.
      throw new HttpsError("invalid-argument", "apartmentNo is required.");
    }
    const floor = typeof data.floor === "string" && data.floor.trim().length > 0 ? data.floor.trim() : null;
    const addressDescription =
      typeof data.addressDescription === "string" && data.addressDescription.trim().length > 0
        ? data.addressDescription.trim()
        : null;
    const buildingNoOverride =
      typeof data.buildingNoOverride === "string" && data.buildingNoOverride.trim().length > 0
        ? data.buildingNoOverride.trim()
        : null;
    const isDefault = data.isDefault === true;
    const addressId = typeof data.addressId === "string" && data.addressId.length > 0 ? data.addressId : null;

    // Faz P.2 §5 — independent server-side re-resolution. A fresh
    // server-generated session token, deliberately not whatever the
    // client's own autocomplete session used — this is a distinct,
    // independent verification call, not a continuation of the client's
    // session.
    const fn: PlaceDetailsFn = defaultPlaceDetailsFn();
    const raw = await fn(resolveApiKey(), placeId, randomUUID());
    if (!raw) {
      throw new HttpsError("not-found", "Unknown or unresolvable place id.");
    }
    const normalized = normalizePlaceDetails(placeId, raw);
    const verified = isSufficientlyResolved(normalized);

    // Faz P.2 §6 — building number: provider value when available, else
    // the customer's own input, with provenance preserved. Never marks a
    // customer-only building number as provider-verified.
    let buildingNo: string | null;
    let buildingNoSource: "provider" | "customer" | null;
    if (normalized.streetNumber) {
      buildingNo = normalized.streetNumber;
      buildingNoSource = "provider";
    } else if (buildingNoOverride) {
      buildingNo = buildingNoOverride;
      buildingNoSource = "customer";
    } else {
      buildingNo = null;
      buildingNoSource = null;
    }

    // FRAUD-F.1 — process the optional, fully client-controlled foreground
    // device-location candidate. Never blocks/fails the address save:
    // every step below is defensive (parse never throws; reverse-geocode
    // and distance are wrapped/guarded so a failure just leaves the
    // corresponding interpretation field null), matching the approved
    // architecture's §8 explicitly. See
    // docs/fraud_evidence_architecture.md FRAUD-F.1 for the full design
    // and the atomic-coupling justification (§ "Failure/atomicity").
    const parsedCandidate = parseDeviceLocationCandidate(data.deviceLocationCandidate);

    let interpretation: ServerFraudInterpretation = {
      policyVersion: FRAUD_F1_POLICY_VERSION,
      phoneVerified:
        typeof request.auth.token?.phone_number === "string" &&
        request.auth.token.phone_number.length > 0,
      appCheckState: request.app ? "VERIFIED" : "MISSING",
    };

    if (parsedCandidate.availability === "available" && parsedCandidate.clientLocation) {
      const deviceLat = parsedCandidate.clientLocation.latitude;
      const deviceLon = parsedCandidate.clientLocation.longitude;

      // distanceMeters only if the SELECTED address itself resolved
      // coordinates — normalized.latitude/longitude can be null when the
      // provider only partially resolved the place (§6/§5 of the
      // approved architecture: never fabricate a distance from a missing
      // reference point).
      if (normalized.latitude !== null && normalized.longitude !== null) {
        interpretation = {
          ...interpretation,
          distanceMeters: distanceMeters(
            normalized.latitude,
            normalized.longitude,
            deviceLat,
            deviceLon,
          ),
        };
      }

      // Independent reverse-geocode of the DEVICE point only — never the
      // selected address's own already-resolved fields (§6). Never
      // throws: a failure here means the derived fields simply stay
      // null; the raw coordinates/accuracy remain valid evidence
      // regardless (§8's explicit "reverse-geocode failure" case).
      try {
        const reverseGeocode: ReverseGeocodeFn = defaultReverseGeocodeFn();
        const devicePlaceId = await reverseGeocode(resolveApiKey(), deviceLat, deviceLon);
        if (devicePlaceId) {
          const deviceRaw = await fn(resolveApiKey(), devicePlaceId, randomUUID());
          if (deviceRaw) {
            const deviceNormalized = normalizePlaceDetails(devicePlaceId, deviceRaw);
            interpretation = {
              ...interpretation,
              province: deviceNormalized.provinceName,
              district: deviceNormalized.districtName,
              neighborhood: deviceNormalized.neighborhoodName,
              street: deviceNormalized.routeName,
              // Never fabricated — null stays null when the provider
              // didn't resolve a building number (§6).
              buildingNumber: deviceNormalized.streetNumber,
              formattedAddress: deviceNormalized.formattedAddress,
              providerPlaceId: deviceNormalized.providerPlaceId,
            };
          }
        }
      } catch (error) {
        logger.warn(
          "[saveDeliveryAddress] device-location reverse-geocode failed; " +
            "address save proceeds, evidence keeps raw coordinates only.",
          { message: error instanceof Error ? error.message : String(error) },
        );
      }
    }

    const db = getFirestore();
    const collection = db.collection("customerAddresses");
    const now = new Date().toISOString();

    const savedAddressId = await db.runTransaction(async (tx) => {
      let docRef = addressId ? collection.doc(addressId) : collection.doc();
      let createdAt = now;

      if (addressId) {
        const existing = await tx.get(docRef);
        if (!existing.exists) {
          throw new HttpsError("not-found", "Address not found.");
        }
        const existingData = existing.data()!;
        if (existingData.uid !== uid) {
          throw new HttpsError("permission-denied", "You do not own this address.");
        }
        createdAt = typeof existingData.createdAt === "string" ? existingData.createdAt : now;
      }

      // §7 — "default address": at most one default per customer. Unset
      // any other default before setting this one, inside the same
      // transaction as the write itself.
      if (isDefault) {
        const priorDefaults = await tx.get(
          collection.where("uid", "==", uid).where("isDefault", "==", true),
        );
        for (const doc of priorDefaults.docs) {
          if (doc.id === docRef.id) continue;
          tx.set(doc.ref, { isDefault: false, updatedAt: now }, { merge: true });
        }
      }

      tx.set(docRef, {
        uid,
        label: label.trim(),
        isDefault,
        apartmentNo: apartmentNo.trim(),
        floor,
        addressDescription,
        buildingNoOverride,
        verificationStatus: verified ? "verified" : "unverified",
        verifiedAt: verified ? now : null,
        providerSource: "google_places",
        providerPlaceId: normalized.providerPlaceId,
        provinceName: normalized.provinceName,
        districtName: normalized.districtName,
        neighborhoodName: normalized.neighborhoodName,
        streetName: normalized.routeName,
        buildingNo,
        buildingNoSource,
        latitude: normalized.latitude,
        longitude: normalized.longitude,
        formattedAddress: normalized.formattedAddress,
        createdAt,
        updatedAt: now,
      });

      // FRAUD-F.1 — created inside the SAME transaction as the address
      // write itself, a deliberate, disclosed atomic-coupling choice (not
      // the best-effort/after-commit approach FRAUD-F.0's own doc
      // originally sketched — see docs/fraud_evidence_architecture.md
      // FRAUD-F.1 "Failure/atomicity" for the full reasoning). Safe
      // because every fallible step (reverse-geocode, distance) already
      // happened above, outside the transaction, and was reduced to a
      // plain, already-validated data object — this `tx.set` itself is as
      // unlikely to fail as the address write immediately above it, which
      // this app already accepts as the availability bar for
      // `saveDeliveryAddress`. Never references organizationId/branchId/
      // orderId — this is pre-order evidence (FRAUD-F.0 §4).
      createFraudEvidenceInTransaction(tx, db, {
        kind: "addressSave",
        subjectUid: uid,
        savedAddressId: docRef.id,
        priorEvidenceId: null,
        clientLocation: parsedCandidate.clientLocation,
        availability: parsedCandidate.availability,
        unavailableReason: parsedCandidate.unavailableReason,
        serverReceivedAt,
        createdAt: now,
        expiresAt: null, // no production retention duration defined yet (FRAUD-F.0 §10).
        organizationId: null,
        branchId: null,
        orderId: null,
        interpretation,
      });

      return docRef.id;
    });

    return {
      addressId: savedAddressId,
      verificationStatus: verified ? "verified" : "unverified",
    };
  },
);

/**
 * Faz P.2.1 §2 — reverse-resolves a customer-adjusted map pin position
 * back into a real, server-verified place, reusing the exact same
 * Place-Details-based resolution [resolveAddressPlace] already uses (via
 * [defaultPlaceDetailsFn]) once a candidate placeId is found — no second,
 * parallel address-resolution code path. Returns `resolved: null` (never
 * throws `NOT_FOUND`) when the point cannot be reverse-geocoded at all,
 * so the client can show a friendly "bu konum çözümlenemedi" message
 * rather than a hard error — matches [saveDeliveryAddress]'s own
 * "keep it unverified, don't reject outright" philosophy.
 *
 * The response's `resolved.providerPlaceId` (when present) is what the
 * client then passes to [saveDeliveryAddress] as its `placeId` — the
 * *only* way a moved pin can ever affect what gets saved, and it still
 * goes through that callable's own independent re-resolution. There is
 * no path from a raw client-supplied `{latitude, longitude}` directly
 * into `customerAddresses` — Faz P.2.1 §6's "no second address source of
 * truth."
 */
export const reverseGeocodeAddressPoint = onCall(
  { secrets: [googlePlacesServerKey], enforceAppCheck: shouldEnforceAppCheck() },
  async (request): Promise<ResolveAddressResult> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in is required.");
    }
    const latitude = request.data?.latitude;
    const longitude = request.data?.longitude;
    if (typeof latitude !== "number" || typeof longitude !== "number") {
      throw new HttpsError("invalid-argument", "latitude and longitude are required numbers.");
    }

    const reverseGeocode: ReverseGeocodeFn = defaultReverseGeocodeFn();
    const placeId = await reverseGeocode(resolveApiKey(), latitude, longitude);
    if (!placeId) {
      return {
        resolved: {
          providerPlaceId: "",
          formattedAddress: null,
          provinceName: null,
          districtName: null,
          neighborhoodName: null,
          routeName: null,
          streetNumber: null,
          latitude: null,
          longitude: null,
        },
        sufficientlyResolved: false,
      };
    }

    const detailsFn: PlaceDetailsFn = defaultPlaceDetailsFn();
    const raw = await detailsFn(resolveApiKey(), placeId, randomUUID());
    if (!raw) {
      throw new HttpsError("not-found", "Reverse-geocoded place could not be resolved.");
    }
    const normalized = normalizePlaceDetails(placeId, raw);
    return { resolved: normalized, sufficientlyResolved: isSufficientlyResolved(normalized) };
  },
);
