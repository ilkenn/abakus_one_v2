import { test } from "node:test";
import assert from "node:assert";
import { resolveGoogleMapsProviderMode } from "../googleMapsProviderMode";
import {
  defaultAutocompleteFn,
  defaultPlaceDetailsFn,
  realAutocomplete,
  realPlaceDetails,
} from "../googlePlacesClient";
import { defaultReverseGeocodeFn, realReverseGeocode } from "../googleGeocodingClient";
import { resolveApiKeyWith } from "../deliveryPlaces";

/**
 * Paket Servis P.3 §D17 — proves the corrected provider-mode separation:
 * "running under the Firebase Functions emulator" and "use offline
 * fixtures" are now two fully independent decisions. Every test here is a
 * plain, network-free unit test (no emulator required) — [resolveGoogle
 * MapsProviderMode] and the `default*Fn()` factories are pure functions of
 * `process.env`/reference equality; [resolveApiKeyWith] takes an
 * injectable secret reader precisely so its failure path is testable the
 * same way, matching this codebase's established `ReverseGeocodeFn`/
 * `PlaceDetailsFn`/`AutocompleteFn` "exported handler + explicit fake"
 * convention (`googlePlacesClient.ts`'s own doc comment).
 */

function withEnv(overrides: Record<string, string | undefined>, run: () => void): void {
  const original: Record<string, string | undefined> = {};
  for (const key of Object.keys(overrides)) {
    original[key] = process.env[key];
    const next = overrides[key];
    if (next === undefined) delete process.env[key];
    else process.env[key] = next;
  }
  try {
    run();
  } finally {
    for (const key of Object.keys(original)) {
      const prior = original[key];
      if (prior === undefined) delete process.env[key];
      else process.env[key] = prior;
    }
  }
}

test("resolveGoogleMapsProviderMode: FUNCTIONS_EMULATOR / FIRESTORE_EMULATOR_HOST alone do NOT force fixture mode", () => {
  withEnv(
    {
      GOOGLE_MAPS_PROVIDER_MODE: undefined,
      FUNCTIONS_EMULATOR: "true",
      FIRESTORE_EMULATOR_HOST: "127.0.0.1:8080",
    },
    () => {
      assert.strictEqual(resolveGoogleMapsProviderMode(), "live");
    },
  );
});

test("resolveGoogleMapsProviderMode: explicit fixture mode is honored", () => {
  withEnv({ GOOGLE_MAPS_PROVIDER_MODE: "fixture" }, () => {
    assert.strictEqual(resolveGoogleMapsProviderMode(), "fixture");
  });
});

test(
  "resolveGoogleMapsProviderMode: an unset or unrecognized value always defaults to live — " +
    "production/staging can never silently enter fixture mode",
  () => {
    withEnv({ GOOGLE_MAPS_PROVIDER_MODE: undefined }, () => {
      assert.strictEqual(resolveGoogleMapsProviderMode(), "live");
    });
    withEnv({ GOOGLE_MAPS_PROVIDER_MODE: "FIXTURE" }, () => {
      // Case-sensitive on purpose — an accidental typo/casing mismatch in a
      // deployed environment's config must fail safe (live), never
      // silently be interpreted as an intentional fixture opt-in.
      assert.strictEqual(resolveGoogleMapsProviderMode(), "live");
    });
    withEnv({ GOOGLE_MAPS_PROVIDER_MODE: "" }, () => {
      assert.strictEqual(resolveGoogleMapsProviderMode(), "live");
    });
  },
);

test("default*Fn(): explicit fixture mode routes every provider seam to its deterministic fixture implementation", () => {
  withEnv({ GOOGLE_MAPS_PROVIDER_MODE: "fixture" }, () => {
    assert.notStrictEqual(defaultAutocompleteFn(), realAutocomplete);
    assert.notStrictEqual(defaultPlaceDetailsFn(), realPlaceDetails);
    assert.notStrictEqual(defaultReverseGeocodeFn(), realReverseGeocode);
  });
});

test(
  "default*Fn(): explicit live mode routes every provider seam to the real-provider implementation " +
    "abstraction (reference-compared only — this test never actually invokes it, so no real " +
    "network/Google call happens)",
  () => {
    withEnv({ GOOGLE_MAPS_PROVIDER_MODE: "live" }, () => {
      assert.strictEqual(defaultAutocompleteFn(), realAutocomplete);
      assert.strictEqual(defaultPlaceDetailsFn(), realPlaceDetails);
      assert.strictEqual(defaultReverseGeocodeFn(), realReverseGeocode);
    });
  },
);

test("resolveApiKeyWith: fixture mode never reads the secret at all, even if the reader would throw", () => {
  withEnv({ GOOGLE_MAPS_PROVIDER_MODE: "fixture" }, () => {
    let readerCalled = false;
    const key = resolveApiKeyWith(() => {
      readerCalled = true;
      throw new Error("must never be called in fixture mode");
    });
    assert.strictEqual(readerCalled, false);
    assert.strictEqual(typeof key, "string");
    assert.ok(key.length > 0);
  });
});

test("resolveApiKeyWith: live mode with a working secret reader returns the real value", () => {
  withEnv({ GOOGLE_MAPS_PROVIDER_MODE: "live" }, () => {
    const key = resolveApiKeyWith(() => "a-real-looking-key-value");
    assert.strictEqual(key, "a-real-looking-key-value");
  });
});

test(
  "resolveApiKeyWith: live mode with a missing/throwing secret reader fails clearly " +
    "(failed-precondition) — never silently falls back to a fixture value",
  () => {
    withEnv({ GOOGLE_MAPS_PROVIDER_MODE: "live" }, () => {
      assert.throws(
        () =>
          resolveApiKeyWith(() => {
            throw new Error("Secret Manager: GOOGLE_PLACES_SERVER_KEY not accessible");
          }),
        (error: unknown) => {
          const httpsError = error as { code?: string; message?: string };
          assert.strictEqual(httpsError.code, "failed-precondition");
          assert.ok(!(httpsError.message ?? "").includes("fixture"));
          return true;
        },
      );
    });
  },
);

test(
  "resolveApiKeyWith: live mode with a secret reader returning an empty string also fails clearly " +
    "— an empty value is not treated as a usable key",
  () => {
    withEnv({ GOOGLE_MAPS_PROVIDER_MODE: "live" }, () => {
      assert.throws(
        () => resolveApiKeyWith(() => ""),
        (error: unknown) => {
          const httpsError = error as { code?: string };
          assert.strictEqual(httpsError.code, "failed-precondition");
          return true;
        },
      );
    });
  },
);
