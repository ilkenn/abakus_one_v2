# Kurye Havuzu + FCM — Gerçek Cihaz Testi (dev projesi)

This is the step-by-step real-device test for Faz 3a–3c (ADR-076, ADR-077, ADR-078). It runs against
the development Firebase project `abakus-one-dev`, never production.

## 0. Prerequisites

| # | Step | Who |
|---|---|---|
| 0.1 | `abakus-one-dev` is on the **Blaze** plan (Cloud Functions needs it). | Product owner (Firebase console) |
| 0.2 | Firebase CLI is signed in on this machine with access to `abakus-one-dev` (`firebase login`, then check with `firebase projects:list`). | Product owner |
| 0.3 | A service account key for `abakus-one-dev`, used by the seed scripts (`GOOGLE_APPLICATION_CREDENTIALS`). Never committed. | Product owner |
| 0.4 | **iOS only:** an APNs Authentication Key uploaded in Firebase console → Project settings → Cloud Messaging → Apple app configuration, for the `abakus-one-dev` iOS app. | Product owner (Apple Developer account) |
| 0.5 | **iOS only:** in Xcode → Runner → Signing & Capabilities, add **Push Notifications**. This creates the `aps-environment` entitlement, which the repo does not have yet. Background Modes → Remote notifications is already set in `Info.plist`. | Product owner (needs the signing team) |

## 1. Deploy (needs explicit approval for each run)

Claude runs these commands only after the product owner explicitly approves that specific run:

```
firebase deploy --project abakus-one-dev --only firestore:rules,firestore:indexes
firebase deploy --project abakus-one-dev --only functions
```

The first `functions` deploy uploads the whole codebase. That takes long and may ask to create
Eventarc/Pub/Sub service agents for the Firestore triggers.

## 2. Data

Prerequisite (product owner, once): Firebase console → abakus-one-dev → Authentication → Get started
→ enable **Email/Password**. Staff sign in with e-mail and password; without it every sign-in fails.

Run from `functions/`, with `GCLOUD_PROJECT=abakus-one-dev` and
`GOOGLE_APPLICATION_CREDENTIALS=<service-account.json>` set for every step (2026-11-13: the
provisioning scripts now allow `abakus-one-dev`). Every step is idempotent except step 2, which runs
once per project.

1. `node scripts/create_dev_test_owner_account.mjs` — creates `sahip.test@abakus.dev` and prints its
   uid (and its password, once).
2. `node scripts/bootstrap_platform_owner.mjs <uid>` — makes that account the Platform Owner.
3. `WEB_API_KEY=<web apiKey from lib/firebase_options_development.dart> node scripts/seed_staging_baseline.mjs <uid>`
   — organization `org-1`, restaurant `restaurant-1`, branch `branch-1`, a starter menu and tables.
4. `npm run build && node scripts/migrate_canonical_catalog_to_project.mjs --project abakus-one-dev`
   — the full menu (run `dart run tool/export_menu_catalog.dart` first if the Dart catalog changed).
5. `node scripts/provision_launch_tables.mjs --project abakus-one-dev` — the 12 launch tables.
6. `node scripts/provision_launch_entitlements.mjs --project abakus-one-dev` — `pos`, `kds`, `qrMenu`
   and, on dev only, `courier`.
7. `node scripts/seed_courier_pool_device_test.mjs org-1 branch-1 restaurant-1` — service areas
   Kadıköy: Caferağa (min. 250 TL, ~35 dk), Moda (min. 300 TL, ~40 dk), Fenerbahçe (no minimum,
   ~30 dk); the branch's default district `kadikoy`; and the staff sign-ins.
   - Since ADR-085, staff sign in with **phone number + password**, on the phone through "Şifre ile giriş"
     and on the Windows POS.
   - Test numbers (dev only, no SMS):

     | Number | Account |
     |---|---|
     | 555 000 00 01 | Yönetici |
     | 555 000 00 02 | Müdür |
     | 555 000 00 03 | Kasiyer |
     | 555 000 00 04 | Dükkan Kuryesi |
     | 555 000 00 05 | Dış Kurye 1 |
     | 555 000 00 06 | Dış Kurye 2 |

   - Accounts created earlier with an `@abakus.dev` e-mail are moved to their number in place: same
     account, same password.
   - `sahip.test@abakus.dev` keeps its e-mail sign-in for the Platform Konsolu.
   - New passwords are printed once.

## 3. Devices

A `development` build uses the local emulator unless it is built with
`--dart-define=FIREBASE_USE_EMULATOR=false` (ADR-084). Every device in this test needs that flag.

- **POS:** Windows,
  `flutter run -d windows --dart-define=ENVIRONMENT=development --dart-define=FIREBASE_USE_EMULATOR=false`.
  At Personel Girişi, sign in with the Müdür's phone number and password and register the device. A
  second manager-tier account approves the registration, for example the Yönetici (555 000 00 01)
  from a phone.
- **Phones** (Android; iOS only if prerequisites 0.4–0.5 are done): install the development APK,
  built with
  `flutter build apk --profile --flavor development --split-per-abi --target-platform android-arm64 --dart-define=ENVIRONMENT=development --dart-define=FIREBASE_USE_EMULATOR=false`
  (output: `build/app/outputs/flutter-apk/app-arm64-v8a-development-profile.apk`). A debug build is no
  longer needed: staff sign-in works in every build.
  - On the sign-in screen, tap "Şifre ile giriş" and use a courier's number (555 000 00 04 / 05 / 06)
    with its password.
  - Then go to Profil → "Yönetim Paneline Geç". Allow notifications when asked.
- **Cashier phone** (to see the staff push): Kasiyer, 555 000 00 03.

## 4. Scenario

| # | Action | Expected |
|---|---|---|
| 4.1 | POS → Kurye Dağıtımı → Kurye Ayarları → Kuryeler: create (quick add) or edit three couriers. Link Dükkan Kuryesi (555 000 00 04) as Dükkan Kuryesi, and Dış Kurye 1 / 2 (555 000 00 05 / 06) as Dış Kurye with district "Kadıköy". | Each roster row shows "Giriş: …". A cashier account trying to link is refused with "yalnızca müdür ve üstü". |
| 4.2 | Courier phones: open Kurye Ekranım. | The dükkan courier sees only "Görevlerim". The dış couriers also see "Havuz" and "Taleplerim". |
| 4.3 | POS: new Paket Servis order in Caferağa, cash. On the dispatch board, tap "Havuza Gönder". | The row shows "Havuzda · talep bekleniyor". |
| 4.4 | Dış Kurye 1 and 2: Havuz → the package (neighborhood, address and amount only, **no name or phone**) → "Talep Oluştur". | POS: the "Havuz Talepleri" badge shows 2 and the alert sounds twice. **Cashier phone: push "Yeni kurye talebi"** (in the foreground too, as a system notification). Tapping it opens Admin → Teslimat Dağıtımı. |
| 4.5 | POS: approve Dış Kurye 2's request. | Order still in the kitchen: "Paket size ayrıldı" push to Dış Kurye 2. Order ready: "Yeni teslimat" push and status "Teslim alınacak". Dış Kurye 1 gets "Havuz talebi sonuçlandı — başka bir kuryeye verildi". |
| 4.6 | Kitchen marks the order ready (if it was reserved). On the POS, tap "Dış Kurye 2 Ata". | Dış Kurye 2: "Yeni teslimat" push. On the phone: "Ara" calls the customer. |
| 4.7 | Dış Kurye 2: "Yola Çıktım", then "Teslim Ettim" → Multinet. | POS row shows "Kurye yolda", then "Teslim Edildi — Mutabakat Bekliyor". The courier card no longer offers "Ara" (KVKK). |
| 4.8 | POS → Kurye Hesap Kapat → Dış Kurye 2. | Multinet is preselected ("Kurye bildirdi: Multinet"). Closing completes the order, and the package disappears from the courier's screen. |
| 4.9 | A second order, directly assigned to the Dükkan Kuryesi ("Kurye Ata"). | The dükkan courier gets a "Yeni teslimat" push and never sees the pool. |
| 4.10 | App in the background, or killed: repeat 4.4 and 4.9. | The system notification appears. Tapping it opens the app at the right screen. |

## 5. Not covered

- FCM content and recipients are verified by emulator tests. The emulator never calls Google, so the
  real delivery is what this checklist tests.
- The Windows POS has no FCM, by design: it uses the live badge and alert sound.
