# Abaküs — Architecture Decision Records

## ADR-001 — Müşteriye Görünen Uygulama Adı

- Tarih: 2026-07-17
- Durum: Accepted

### Karar
Müşterinin uygulamada göreceği isim yalnızca **Abaküs** olacaktır.

### Sonuçlar
- Splash, launcher label, ekran başlıkları ve mağaza metinlerinde `Abaküs` kullanılır.
- `abakus_one_v2` yalnızca teknik proje klasörü/package bağlamındadır.
- UI içinde teknik proje adı gösterilmez.

---

## ADR-002 — Feature-First Mimari

- Tarih: 2026-07-17
- Durum: Accepted

### Karar
Proje feature-first ve katmanlı mimari kullanacaktır.

### Sonuçlar
- Her iş özelliği `lib/features/<feature_name>` altında bulunur.
- Feature'lar presentation dosyalarını birbirinden doğrudan import etmez.
- Ortak kod `core` veya `shared` altına taşınır.

---

## ADR-003 — Gemini Kontrollü Kod Üretimi

- Tarih: 2026-07-17
- Durum: Accepted

### Karar
Gemini tüm projeyi tek promptla üretmeyecek; görevler küçük ve kontrollü dosya kapsamlarıyla verilecektir.

### Sonuçlar
- Her görevde değiştirilebilecek dosyalar açıkça belirtilir.
- Mevcut içeriği paylaşılmayan dosyalar Gemini tarafından yeniden yazılmaz.
- Her görev Architecture Bible ve Master Prompt bağlamıyla yürütülür.
- Kod üretimi sonrası analiz ve test komutları çalıştırılır.

---

## ADR-004 — Tasarım Token Zorunluluğu

- Tarih: 2026-07-17
- Durum: Accepted

### Karar
Renk, typography, spacing, radius, shadow, route ve asset path değerleri ekranlarda hard-code edilmeyecektir.

### Sonuçlar
Merkezi sınıflar kullanılır:
```text
AppColors
AppTypography
AppSpacing
AppRadius
AppShadows
AppRoutes
AssetPaths
```

---

## ADR-005 — Backend Platform Selection

- Date: 2026-07-25
- Status: Accepted

### Decision
Abaküs One will use Firebase (Firestore, Cloud Functions, Firebase Auth, Remote Config,
Crashlytics, Analytics, Cloud Messaging, Storage, App Check) as its backend platform.

### Context
No backend existed prior to this decision. `firebase.json`/`lib/firebase_options.dart` were
pre-configured via the FlutterFire CLI but not integrated (no `firebase_core` dependency, no
`Firebase.initializeApp()` call, no iOS `GoogleService-Info.plist`). Alternatives evaluated:
Supabase (Postgres) and a fully custom backend, across authentication, primary datastore, server
logic, Remote Config, Crashlytics, Analytics, Cloud Messaging, Storage, multi-tenancy, cost,
scalability, offline capability, security, development speed, Flutter integration, and future
AI/vector-search needs.

Firebase was selected primarily on the strength of five factors verified directly against this
project: a Flutter-first architecture (FlutterFire's multi-year maturity has no equivalent
elsewhere), the offline-first POS requirement (independently documented in
`docs/module_catalog.md` as the hardest single requirement in the entire roadmap, and directly
addressed by Firestore's mature built-in offline sync — the leading alternative has no
comparable capability without a third-party sync layer), the breadth of the free first-party
Firebase ecosystem (Remote Config, Crashlytics, Analytics, Cloud Messaging), the fact that three
service seams already exist in this codebase (`RemoteConfigService`, `CrashReportingService`,
`AnalyticsService`) — with `RemoteConfigService`'s method signatures matching the Firebase
Remote Config SDK almost exactly — and alignment with the existing roadmap and this session's
governance agents (`firebase_engineer.md`, `security_engineer.md`), which were already written
assuming this outcome.

Firestore's weaker fit for the project's relational/reporting workloads (recipe costing,
multi-branch financial reporting) was weighed as the primary counter-argument and is addressed
under Consequences below, not dismissed.

### Consequences
- `firebase_core` and per-product Firebase packages are added incrementally, each as its own
  scoped, approved task (starting with P1-003) — never speculatively.
- The reporting/costing architecture (`COST`, `FIN`, `RPT` modules) **must remain compatible
  with future export into BigQuery or another analytical warehouse**, should business scale
  require it. This is a flexibility requirement on the data model and access patterns chosen
  later — not a mandatory build commitment in Phase 1 or any specific phase. No warehouse/export
  pipeline is being built now.
- Multi-tenant isolation is enforced via Firestore Security Rules + App Check, per
  `security_engineer.md`'s and `firebase_engineer.md`'s existing standards.
- `RemoteConfigService`'s real implementation (P1-008) proceeds against `firebase_remote_config`.
- iOS Firebase setup (`GoogleService-Info.plist`) is completed as part of the first real
  Firebase-integration task, not this ADR.
- This decision is treated as settled per `ENGINEERING_CONSTITUTION.md`'s No Silent Decisions
  principle — it is not re-litigated on a later task without genuinely new information (e.g. a
  concrete, measured cost or scaling problem in production).

### Confidence
82%. Raised from the initial 75% assessment for two reasons: (1) softening the BigQuery/warehouse
requirement from a mandatory build item to a compatibility constraint removes the most concrete
execution risk originally named; (2) re-weighing the five verified factors above (Flutter-first
fit, the offline POS requirement, the first-party ecosystem, the existing service seams, and
alignment with the already-written roadmap and governance agents) confirms they are strong,
project-specific evidence, not generic vendor preference. The remaining 18% is held back
deliberately: no hands-on technical spike was performed (this is codebase- and
documentation-evidence-based analysis), and Firestore's cost predictability and relational-
reporting fit remain unproven against real production data.