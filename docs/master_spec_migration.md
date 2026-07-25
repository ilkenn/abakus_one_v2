# Master Specification v1.0 Migration — Assumption Log

> Status: in progress, screen by screen. This log records every place the Master Specification
> (18 documents, `01_PRODUCT_VISION` → `18_WORKFLOW`) was ambiguous or silent for a screen actually
> being built, and the assumption made to proceed — per the explicit instruction to state
> assumptions rather than invent silently. Update this file every time a new screen is migrated.

## Migration order

Splash → Onboarding → Login → Home → Menu → Bowl Builder → ... (one screen at a time, each
verified against the spec before moving to the next, per the user's own stated plan).

## Standing rule: screen-local illustration colors vs. the Design System (2026-07-22)

The AI Development Constitution's Design Protection clause bans introducing colors outside the
Design System. Resolved distinction, confirmed with the user: this governs general-purpose UI
colors (surfaces, text, status, anything that could plausibly be reused as a token elsewhere) — it
does not require a one-off piece of brand illustration (an animated mark, a hero graphic, a mascot)
to invent its palette from `AppColors`, since that system has no concept of "illustration palette"
to begin with. Such colors may live as documented local `const`s scoped to the widget that owns the
illustration (see `SplashAbacusAnimation`'s bead/wood palette and `SplashScreen`'s
`_SplashPalette` for the pattern), provided they're called out explicitly here rather than added
silently. Anything with a plausible second use as a general UI color still belongs in `AppColors`,
not as a local exception.

## Global: design tokens (`lib/core/theme/`)

The spec is explicit that *no component may define its own visual values outside the design
system* (§05) and that colors/spacing/typography/radii/shadows must come from it (§15). Since the
token files are shared by every screen, they were brought in line with the spec **before** Splash
was built, rather than duplicating spec-correct values inline in `splash_screen.dart` only.

### Colors (`app_colors.dart`)

Every color §05 names explicitly now equals its exact hex value: `primary`, `primaryLight`,
`background`, `surface`, `surfaceVariant`, `border`, `textPrimary`, `textSecondary`,
`textDisabled`, `success`, `warning`, `error`. `primaryExtraLight` (`#EAF3EC`) was added — §05
names it as a third primary-family tier that didn't exist as a token before.

**Assumptions** (tokens the spec never names, but the codebase already depended on):
- `onPrimary = #FFFFFF` — the spec never defines this pairing token, but white-on-a-dark-saturated-
  green primary is the only defensible reading, and it happens to already match the pre-spec value.
- `divider = border`'s new value — the spec defines exactly one line-color token ("Border"), not a
  separate divider color. Assumed they're the same concept.
- `primaryDark`, `secondary`, `accent`, `info`, `overlay`, `scrim` — not covered by the spec at
  all. Left at their pre-spec values because `app_theme.dart` and every not-yet-migrated screen
  still reference them; deleting or repurposing them now would break compilation far outside this
  task's scope. They'll be reconciled (or formally dropped) as their consuming screens get their
  own migration turn.

### Typography (`app_typography.dart`)

`displayLarge`, `headlineLarge`, `headlineMedium`, `titleLarge`, `titleMedium`, `bodyLarge`,
`bodyMedium`, `bodySmall` now hold §05's exact Type Scale pixel sizes for their corresponding tier
("Display Large" → `displayLarge`, "Heading Large" → `headlineLarge`, etc. — position-mapped since
the spec's naming and the codebase's pre-existing naming don't use identical words for the same
tier). `displayMedium` and `caption` were added — §05 names both as scale tiers that had no token
before. Every weight above 700 (the spec's declared maximum, "700 Bold") was clamped down to 700;
the spec enumerates exactly four weights (400/500/600/700) and nothing else.

**Assumptions**:
- **Font family**: §05 specifies "SF Pro Display" primary, Inter/Roboto fallback. No font asset or
  package (e.g. `google_fonts`) exists in this repo (`pubspec.yaml` declares none). Sourcing and
  licensing real font files is its own task, not a token-value edit — `fontFamily` is left unset
  (Flutter's platform default) until that work happens. Every screen built against these tokens
  until then will look correct in size/weight/color but not in typeface.
- `labelLarge`, `labelMedium`, `priceLarge`, `priceMedium` aren't named tiers in §05's scale at
  all. Kept (many not-yet-migrated screens depend on them) with sizes untouched, weights clamped
  to ≤700 like everything else.
- Letter-spacing values (e.g. `displayLarge`'s `-1.0`) aren't mentioned anywhere in the spec. Kept
  as pre-existing aesthetic choices rather than invented or zeroed out.

### Radius (`app_radius.dart`)

`medium` (12), `large` (16), `extraLarge` (24) already matched §05's Radius Tokens exactly.
`small` moved from a pre-spec `6` to `8` — the spec's nearest defined value (its scale starts at 8).
`pill` (99) is kept as-is: not one of the spec's discrete size tokens, but a shape utility for
fully-rounded elements (pills/circular avatars), not a "size decision" in the sense §05 is
regulating.

### Spacing (`app_spacing.dart`)

No changes. §05's Spacing Tokens list (4, 8, 12, 16, 20, 24, 32, 40, 48, 56, 64, 72, 80) already
contains every value the existing named tokens use (`xs=4, sm=8, md=12, lg=16, xl=24, xxl=32,
xxxl=48`) — already 100% spec-valid, nothing to correct.

### Shadows (`app_shadows.dart`)

No changes. §05's Elevation section only names abstract "Level 1–4" with no concrete blur/offset
numbers to conform to — inventing numbers to fill that gap would itself be "defining a visual value
outside the system." Left untouched until the spec (or a future revision of it) supplies concrete
values. Splash doesn't use shadows regardless (flat, full-bleed design).

## Splash Screen (`lib/features/navigation/presentation/screens/splash_screen.dart`)

**Ambiguity**: the spec's 18 documents cover Product Vision through Community/Architecture/Rules/
Testing/Workflow, but there is no dedicated Splash Screen document (unlike Home/Menu/Bowl Builder/
Product Detail/Cart/Order Tracking/Profile, which each get one). Nothing enumerates required
Splash content, layout, or copy.

**Assumption**: built Splash from the cross-cutting documents that apply to every screen — Product
Vision (§01: premium/calm, "wow" first impression), Brand Identity (§02: premium/calm/confident/
minimal, never loud/flashy), User Psychology (§03: users should feel safe/calm/in control), Design
Philosophy (§04: simplicity over decoration, one clear focal point, generous whitespace, never
overcrowd), and the Design System/Component Library tokens (§§05–06). Concretely:

- Full-bleed `AppColors.primary` background with the mark + wordmark centered — kept the
  pre-existing pattern (this was already how the app's one and only Splash worked before this
  migration) rather than inventing a new layout the spec doesn't mandate either way.
- No tagline. §04's "one message only" (generalized from the Hero Banner rule) and "never overcrowd
  a screen" were read as ruling out extra copy on a screen whose only job is a few seconds of brand
  presence before Onboarding/Login.
- Kept the existing `Icons.blur_on_rounded` mark. The spec has no real logo asset to reference;
  swapping it for a different placeholder icon would be an equally arbitrary, spec-unjustified
  choice, so the already-established one was kept rather than replaced.
- Loading indicator: §06's Loading rules ("skeleton placeholders whenever layout is known") don't
  apply here — there's no known layout to skeleton against on the app's very first frame. Used a
  small, quiet `CircularProgressIndicator` instead, consistent with "avoid blocking the entire
  interface" and the calm/minimal brand tone.
- Every raw `TextStyle`/color the pre-spec version hardcoded inline (`fontSize: 28`,
  `fontWeight: FontWeight.bold`, `letterSpacing: 1.2`, `Colors.white`) was replaced with the shared
  `AppTypography`/`AppColors` tokens — the pre-spec file itself was violating §05/§15's "no
  component defines its own visual values" rule; this migration fixes that in the same pass.

**Brand name correction**: every spec document refers to the product as "Abaküs One" (including the
spec's own title, "Abaküs One Master Specification v1.0"). The pre-spec code said "Abaküs Bowl" in
both `app.dart`'s `MaterialApp.title` and the Splash wordmark. Updated both to "Abaküs One" — not a
new design decision, just correcting the name to what the spec itself consistently calls the
product.

**Functional behavior preserved, not migrated**: the 2-second delay and the
`onboardingCompleteProvider`-driven navigation to `LoginScreen`/`OnboardingScreen` are unrelated to
visual design and were left exactly as they were — the spec's Testing/Development Rules documents
don't ask for navigation-logic changes, only "no design decisions outside the specification," which
concerns appearance, not app flow.

**Update — animated abacus mark replaces the `Icons.blur_on_rounded` placeholder**: the user
directly requested a bespoke animated abacus illustration (colored beads sliding along wires,
staggered per row, physical "settle" overshoot, 60fps target) referencing the real Abaküs One
marketing artwork. This closes the gap this log originally flagged ("no real logo asset to
reference"): `SplashAbacusAnimation`
(`lib/features/navigation/presentation/widgets/splash_abacus_animation.dart`) is a `CustomPainter`-
driven, one-shot (non-repeating) animation — a wood-toned frame with 7 rows of 5 beads each, beads
starting bunched at the wire's left end and fanning out to rest positions with `Curves.easeOutBack`
overshoot, staggered both row-to-row and bead-to-bead so the motion reads as one cascading wave.

**Assumption — bead palette**: the user supplied named colors (Sage Green, Emerald Green,
Terracotta, Mustard Yellow, Deep Blue, Coral, Olive, Warm Orange) as an explicit example palette,
not exact hex values. Chose muted/desaturated hex values for each (e.g. Terracotta `#C1652F`, not a
saturated orange) to read as premium lacquered wood rather than toy-bright primaries, per the
explicit "must not look like a toy" requirement. Used 7 of the 8 named colors (one per row, dropping
Warm Orange since Terracotta/Coral/Mustard already cover the warm end) — this palette is a one-off
decorative illustration, not reusable UI color, so it lives as a local `const` in the widget file
rather than being added to `AppColors`.

**Superseded below**: the "kept the green background" decision immediately above was reversed in the
v2 redesign — see the next section. Left the paragraph in place rather than deleted so the reasoning
trail (why green was chosen first, why it changed) stays legible.

## Splash Screen v2 — cinematic cream redesign

The user judged the v1 redesign (green full-bleed background, mark+wordmark appearing together, a
spinner) as reading like a generic/default splash rather than a premium brand moment, and requested
a full redesign: cream background, a larger abacus, richer wood/bead treatment, "Abaküs" (not
"Abaküs One") as the wordmark with a tagline, no spinner, and a staged cinematic sequence (frame →
beads → logo → tagline → soft transition) landing within the first ~3 seconds.

**Background**: flat `AppColors.primary` replaced with a radial gradient from `AppColors.background`
(`#F8F6F2`) to a new local warm-cream tone `#EDE1CB` — ties to the existing token at one end rather
than inventing an entirely disconnected palette, while matching the reference artwork's warm
backdrop.

**Abacus**: `SplashAbacusAnimation` enlarged ~42% (240×190 → 340×270); wood gradient expanded from 2
stops to 3 (adds actual "grain" read); added a soft blurred contact shadow under the frame for lift;
added thin grain lines; bead palette pushed slightly more vivid while keeping the lacquered-not-toy
treatment; added a small specular highlight per bead for a glossier finish.

**Wordmark/tagline**: "Abaküs One" → "Abaküs" only, colored `AppColors.primary` (ties to the design
system, also happens to match the reference artwork's green logotype almost exactly). Added a
tagline, "DENGENİ BUL, LEZZETİ HİSSET" — taken verbatim from the reference artwork rather than
invented, since the user's reference image showed this exact phrase as the canonical tagline.

**Sequence/timing**: total delay extended from 2000ms to 3000ms to fit a genuine staged reveal
without rushing it: frame fades/scales in first (~30–530ms), beads cascade inside it through
~1600ms (unchanged cascade logic, deliberately overlapped with the frame's own fade rather than
strictly blocking two separate steps — a fluidity choice made before the later Animation System
document's stricter "Background → Frame → Beads → Logo → Slogan" sequencing was supplied; worth a
second look only if the user's visual review flags the overlap), wordmark reveals at 1650ms, tagline
at 2100ms, then a hold until 3000ms when navigation fires. Default `MaterialPageRoute` push replaced
with a `PageRouteBuilder` doing a plain 450ms `FadeTransition` for the "soft transition" ask instead
of the default slide.

**Spinner removed** entirely — the cascade-and-settle animation itself is the "something is loading"
cue, per explicit instruction.

**Accessibility pass (2026-07-22)**, applied against the user-supplied Accessibility Standards
document while Splash was still open for revision:
- Tagline color computed at ~3.7:1 contrast against the background gradient's darker `#EDE1CB` stop
  — below the 4.5:1 WCAG AA minimum for normal text. Darkened `#8A6D4A` → `#6B4E30` (~5.9:1, passes).
  Wordmark color (`AppColors.primary`) was checked too and already clears ~5.75:1 — untouched.
- `WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations` is now read
  once at startup in both `SplashScreen` and `SplashAbacusAnimation`; when true, the staged
  fade/slide reveal and the bead cascade both skip straight to their settled end state instead of
  animating (total navigation delay is unchanged — only the animation itself is skipped, not the
  timing).
- Wrapped the decorative abacus illustration in `ExcludeSemantics` — it's brand decoration, not
  information; "Abaküs" and the tagline already carry the semantic content a screen reader needs.

**Assumption — all-caps tagline vs. Content Guidelines' "no all-caps" rule**: a later-supplied
Content Guidelines document states "Tamamı büyük harf kullanılmaz" (no all-caps) as a general writing
rule, and separately bans "gereksiz büyük harf... kullanımı" (*unnecessary* caps usage). Read the
tagline as a deliberate small-caps-style logotype treatment (matching the reference artwork's actual
rendering) rather than the sentence-case UI copy that rule is aimed at (buttons, messages,
notifications) — kept the literal uppercase string rather than converting to sentence case. Flagged
here rather than silently decided either way; revisit if the user's visual review says otherwise.

## Reference-image-driven redesign (supersedes/extends the Master Spec migration above)

The user later supplied 10 reference mockup images showing the target visual direction more
concretely than the text spec alone, and asked for the app to be brought in line with them without
breaking the existing architecture. Two genuine business-rule conflicts between the earlier
Master Spec reading and the reference images were resolved by asking the user directly rather than
guessing (both answered, both logged below); every other reference-driven decision follows the
same "state the assumption and continue" pattern as the rest of this log.

**Resolved via direct question**:
- Bowl Builder: the earlier "single choice, block when full, only Extras beyond that" rule (built as
  a stated "mandatory business rule") is superseded by the reference images' 6-step
  (Baz/Protein/Sebzeler/Soslar/Crunch/Özet), live-preview, more permissive model. Bowl Builder itself
  has not been rebuilt yet — this only records which model governs when that work happens.
- Home Screen target: the personalized variant (reference image #10 — "Merhaba Ece", Boncuk tasks/
  campaigns) is canonical, not the generic "Bugün ne yesek?" variant (image #1).

### Home Screen v2 (`lib/features/home/presentation/screens/home_screen.dart`)

Rebuilt per image #10 while keeping every existing working piece (restaurant-status card,
`CampaignCarousel`, the "Özel Kuponları Keşfet" banner — still the only entry point to
`CampaignsScreen`, so it was not removed even though newer sections cover related ground) and
fixing a pre-existing bug: the "Son Siparişin" section had never actually been wired to real data —
it built a fake order from `HomeMockData.popularProducts[0]`/`[2]`. Replaced with a real, conditional
"Aktif Siparişin" card backed by `activeOrderProvider` (already existed, already documented as
intended for exactly this).

**Assumptions**:
- Loyalty level card + Şans Çarkı teaser card (new two-card row) both open `LoyaltyScreen` on tap
  rather than duplicating the spin/redeem actions inline on Home — those actions have exactly one
  owner (`LoyaltyNotifier` via `LoyaltyScreen`), consistent with "ana mimariyi bozmadan."
- Bottom quick-action row (Hızlı Teslimat / Gel Al / Rezervasyon / Masada QR Oku): no reservation
  system or pickup-channel flow exists yet, so per the session's established anti-fake-functionality
  rule, "Rezervasyon" shows an honest "yakında eklenecek" SnackBar (matches the QR scanner
  placeholder's precedent) and "Hızlı Teslimat" shows the real current estimated-delivery-minutes
  value rather than inventing one. "Gel Al" jumps to the Menu tab (no separate pickup flow exists to
  route to). The QR action deliberately uses a different icon/label
  (`Icons.qr_code_2_rounded`/"Masada QR Oku") than the bottom-nav QR FAB
  (`Icons.qr_code_scanner_rounded`/"QR ile Sipariş") even though both open the same
  `QrScannerScreen` — an exact duplicate would be ambiguous to both users and widget-finders on a
  screen where both are visible at once.
- Promoted three widgets to `shared/widgets/` since Home became their second consumer, per the
  architecture bible's promotion rule: `BowlBuilderFeatureCard` (was private to `menu_screen.dart`),
  `LoyaltyCampaignCard` (was private `_CampaignCard` in `loyalty_screen.dart`), and `SpinWheelIcon`
  (was private `_WheelPainter`/inline `CustomPaint` in `loyalty_screen.dart`).

## Authentication phase (2026-07-22)

Full project analysis (see the analysis-report memory) surfaced a corrected fact that reshaped this
phase: `LoginScreen`/`OnboardingScreen` actually navigated to `features/main/`'s plain `MainScreen`,
not the richer `features/navigation/`'s `MainNavigationScreen` built and tested earlier this session
— the original orphan-detection grep missed this because relative imports don't spell out the
`features/main/` path literally. Corrected per explicit user decision: all post-auth entry points
(persisted-session auto-login, OTP success, guest) now go to `MainNavigationScreen`;
`features/main/MainScreen` is untouched and left in place, simply no longer referenced.

**Model**: phone + OTP only, per explicit user decision — no email, no password. Login's password
field was removed entirely.

**Environment split**: no project-specific `AppEnvironment` system existed (verified before
building anything) — `authRepositoryProvider` uses Flutter's own `kReleaseMode` constant to choose
between `DevelopmentLocalAuthRepository` (debug/profile — fixed dev OTP code `123456`, real
`flutter_secure_storage`-backed session persistence, self-enforced resend cooldown) and
`ProductionUnavailableAuthRepository` (release — fails closed on every call, never fakes success).

**Guest sessions are never persisted** — `AuthNotifier.loginAsGuest()` only flips `isGuest` in
memory; no `AuthSession`/secure-storage entry is created, so a guest returns to Login on next launch,
by design.

**Session validity**: 30 days, chosen locally (`DevelopmentLocalAuthRepository.sessionValidity`) —
documented as a placeholder a real backend will own outright once one exists.

**Found and fixed mid-build**: `flutter_secure_storage`'s platform channel doesn't throw when
unavailable (e.g. under `flutter test`) — it simply never completes, which `try`/`catch` alone can't
guard against. Added a 2-second timeout in `SecureSessionStorage` around every read/write/clear call
— both the correct production behavior (Splash must never hang waiting on storage) and what fixed
the widget-test suite.

**Assumption, not asked separately**: instructions didn't say whether the OTP screen's own
`OtpNotifier` cooldown display should hardcode a duration or read it polymorphically from whichever
`AuthRepository` is active. Chose the latter (`AuthRepository.resendCooldownDuration` getter) so the
UI never assumes a concrete implementation's constant — consistent with the existing
dependency-abstraction rule, not a new decision axis.

## Next up

Menu — align to the reference images' search+filter+hero+icon-chips+carousel layout, then Bowl
Builder (rebuild per the now-approved 6-step live-preview model above). Restaurant Operations phase
(Kurye/Mutfak) comes after the customer app is complete, per the stated phase order.
