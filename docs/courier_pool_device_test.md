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

1. If `abakus-one-dev` has no tenant, menu or tables yet, seed them first. The platform owner must
   already be bootstrapped (`bootstrap_platform_owner.mjs`). Then run:
   `GCLOUD_PROJECT=abakus-one-dev GOOGLE_APPLICATION_CREDENTIALS=... WEB_API_KEY=... node scripts/seed_staging_baseline.mjs <platformOwnerUid>`
2. Seed the courier-pool test data (service areas Kadıköy: Caferağa / Moda / Fenerbahçe, plus four
   test sign-ins; new passwords are printed once):
   `GCLOUD_PROJECT=abakus-one-dev GOOGLE_APPLICATION_CREDENTIALS=... node scripts/seed_courier_pool_device_test.mjs <organizationId> <branchId> <restaurantId>`

## 3. Devices

- **POS:** Windows, `flutter run -d windows --dart-define=ENVIRONMENT=development`. Sign in with a
  manager account and register the device (approval flow).
- **Courier phones** (Android, and iOS if prerequisites 0.4–0.5 are done):
  `flutter run --flavor development --dart-define=ENVIRONMENT=development`.
  Sign in at Personel Girişi with `kurye.dukkan@` / `kurye.dis1@` / `kurye.dis2@` and allow
  notifications when asked.
- **Cashier phone** (to see the staff push): sign in with `kasiyer.test@`.

## 4. Scenario

| # | Action | Expected |
|---|---|---|
| 4.1 | POS → Kurye Dağıtımı → Kurye Ayarları → Kuryeler: create (quick add) or edit three couriers. Link `kurye.dukkan@` as Dükkan Kuryesi, and `kurye.dis1@` / `kurye.dis2@` as Dış Kurye with district "Kadıköy". | Each roster row shows "Giriş: …". A cashier account trying to link is refused with "yalnızca müdür ve üstü". |
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
