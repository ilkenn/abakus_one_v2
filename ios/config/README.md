# iOS per-environment Firebase configuration

Three real `GoogleService-Info.plist` files, one per environment, fetched
directly from each Firebase project (not hand-written):

- `Development/GoogleService-Info.plist` — `abakus-one-dev`
- `Staging/GoogleService-Info.plist` — `abakus-one-staging`
- `Production/GoogleService-Info.plist` — `abakusone`

**Do not hand-edit these files.** Re-fetch instead:
`firebase apps:sdkconfig IOS <appId> --project <projectId> -o ios/config/<Environment>/GoogleService-Info.plist`.

## Why this isn't wired into Xcode yet

Selecting the right plist per build (Development/Staging/Production, each
across Debug/Release/Profile) requires new Xcode build configurations and
matching schemes in `Runner.xcodeproj` — today there's only the single
default `Runner` scheme with the stock Debug/Release/Profile configurations.
Wiring that up means editing `project.pbxproj` (a fragile, plist-like file
Xcode normally manages for you) and `xcshareddata/xcschemes/*.xcscheme`.

This was deliberately **not** done by hand-editing `project.pbxproj` from
this environment: there is no macOS/Xcode available here to open the result
and confirm it isn't corrupted, and no CI step in this repository builds
for iOS to catch a mistake automatically. A wrong edit could silently break
the iOS project in a way nobody notices until someone opens it in Xcode much
later — a materially worse outcome than leaving this one step manual and
documented. This mirrors the same judgment call already applied to
Windows/Linux auth support in the Phase 2 backlog: prefer an honest gap over
an unverifiable workaround.

None of this blocks Sprint 1's actual behavior: `Firebase.initializeApp()`
(P2-003) is called with an explicit `options:` object resolved by
`FirebaseOptionsSelector` from the Dart side — it does not read
`GoogleService-Info.plist` at all. The plist only matters once a native
Firebase SDK feature that reads it directly (e.g. certain push-notification
setup) is added, which is out of Sprint 1's scope.

## Manual steps to finish iOS flavor wiring (requires Xcode on macOS)

1. In Xcode, **File → New → Configurations**: duplicate `Debug`, `Release`,
   and `Profile` three times each, named `Debug-development`,
   `Debug-staging`, `Debug-production`, `Release-development`, etc. (9 total,
   replacing the original 3).
2. Create three schemes (`development`, `staging`, `production`), each
   mapping its Run/Archive actions to the matching `-development`/
   `-staging`/`-production` configurations from step 1.
3. Add a **Run Script build phase** to the `Runner` target, before
   "Compile Sources", that copies the correct plist for the active
   configuration into `Runner/GoogleService-Info.plist`, e.g.:
   ```sh
   environment="development" # derive from $CONFIGURATION instead of hardcoding
   case "$CONFIGURATION" in
     *-development) environment="Development" ;;
     *-staging) environment="Staging" ;;
     *-production) environment="Production" ;;
   esac
   cp "${SRCROOT}/config/${environment}/GoogleService-Info.plist" \
      "${SRCROOT}/Runner/GoogleService-Info.plist"
   ```
4. Add `Runner/GoogleService-Info.plist` (the copy destination, not the
   files in this folder) to `.gitignore` — it becomes a build artifact once
   step 3 exists, not something to commit.
5. Confirm with `flutter build ios --flavor development --no-codesign`
   (and `staging`/`production`) that each flavor bundles the right plist.
