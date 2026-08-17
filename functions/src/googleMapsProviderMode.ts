/**
 * Explicit, opt-in Google Maps provider-mode switch — Paket Servis P.3
 * §D17. Replaces the previous, incorrect assumption (originally in
 * `googlePlacesClient.ts`/`googleGeocodingClient.ts`/`deliveryPlaces.ts`'s
 * own `isEmulatorContext()`) that "running under the Firebase Functions
 * emulator" (`FIRESTORE_EMULATOR_HOST`/`FUNCTIONS_EMULATOR` present) meant
 * "use offline fixtures." That assumption broke physical-device UX
 * testing: a developer manually running the real app against the local
 * Functions emulator got the *identical* fixture behavior an automated
 * `node --test` run does — every reverse-geocode/search request resolved
 * to the same handful of canned places regardless of real input, making
 * it impossible to genuinely exercise the search/recenter UX by hand.
 *
 * Firebase Functions emulator != automated test fixture mode. The two are
 * now fully decoupled: this module is the *only* thing that decides
 * fixture-vs-live, and it is driven exclusively by an explicit env var,
 * never inferred from emulator presence.
 *
 * **Default is "live"** whenever `GOOGLE_MAPS_PROVIDER_MODE` is not
 * explicitly `"fixture"` — staging/production must never silently enter
 * fixture mode just because some other environment characteristic happens
 * to look emulator-like; only an explicit opt-in does. Automated Functions
 * tests request fixture mode explicitly via the emulator-launching npm
 * scripts themselves (see `functions/package.json`'s `test:emulator`),
 * never via a default this module provides.
 */

export type GoogleMapsProviderMode = "fixture" | "live";

export function resolveGoogleMapsProviderMode(): GoogleMapsProviderMode {
  return process.env.GOOGLE_MAPS_PROVIDER_MODE === "fixture" ? "fixture" : "live";
}
