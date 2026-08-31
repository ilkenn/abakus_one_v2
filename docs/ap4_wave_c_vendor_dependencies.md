# AP-4 Wave C — Fiscal Device Controlled External Dependency Dossier

**Status**: OPEN. This document is the authoritative, explicit record of every real-world dependency
outside this repository's control that blocks a genuine PAX A910SF / GMP-3 / YN ÖKC production
integration — per the governing AP-4 instruction's own requirement that a controlled external
dependency never be treated as a resolved architectural ambiguity by documentation alone.

**Confirmed before any code in this wave was written** (exhaustive repo search, filename glob for
`*pax*`/`*gmp*`/`*fiscal*`/`*.jar`/`*.aar`/`*.zip`/`*sdk*` and content grep for `PAX A910`, `GMP-3`,
`ÖKC`, `fiscal`, across the entire repository excluding `.git`/`node_modules`/`build`/`.dart_tool`):
**zero PAX A910SF SDK, zero GMP-3/YN ÖKC protocol specification, zero vendor credential material, zero
prior fiscal adapter code (stubbed or otherwise) exists anywhere in this repository.** This matches
`docs/payment_cash_fiscal_architecture.md` §4's own already-confirmed finding from AP-1 ("a confirmed
total absence — zero code, stub, interface, domain model, or dependency anywhere in the repository").

## 1. What was built this wave (real, not a placeholder)

- `functions/src/fiscalDomain.ts` — pure, vendor-neutral contracts: `FiscalOperationType`,
  `FiscalOperationStatus` (with a locked, tested state machine — `timedOut` always routes through
  `unknownReconciliationRequired`, never a direct terminal), `FiscalOperationJournalEntry` (append-only
  journal shape), `OfflineLease` + `validateOfflineLeaseForOperation` (pure, fully tested).
- `functions/src/fiscalAdapter.ts` — `FiscalDevicePort` interface, `UnconfiguredFiscalAdapter` (the
  honest "no real device configured" adapter every production deployment actually gets — every
  operation resolves `"unavailable"`, never a fabricated success), `TestOnlyDeterministicFiscalAdapter`
  (emulator-only, structurally unselectable in production via the real `FUNCTIONS_EMULATOR` env var gate
  — proven by `fiscalAdapter.test.ts`'s own production-exclusion test).
- `functions/src/fiscalEngine.ts` — `recordFiscalOperation` (the real journal-write + two-phase
  device-round-trip engine, idempotent, conservation-checked, transaction-ordering-correct),
  `issueOfflineLease`/`revokeOfflineLease` (real, server-authoritative, hard-ceiling-enforced).
- Real offline-authorization wiring into `paymentEngine.ts`'s `recordPaymentAttempt`: an offline-captured
  cash sale, replayed once back online, is validated against a real, server-issued lease (expiry,
  revocation, monotonic-sequence replay protection, cash-only tender restriction, transaction
  count/value caps) — all genuinely tested (`fiscalDomain.test.ts`, `paymentEngine.test.ts`'s own
  offline-lease integration tests).
- `lib/features/pos/domain/offline/*` + `lib/features/pos/data/offline_payment_outbox_repository.dart`
  — a real, durable (survives app restart, proven by a dedicated test reopening a fresh
  `SharedPreferences` handle), tested local outbox for offline-captured cash sales.

**None of the above invents a single PAX command, GMP-3 byte sequence, or fiscal-document field.**

## 2. What is explicitly NOT built, and why

| Item | Owner / source | What's needed | Blocks | Mitigation before writing protocol code | Required acceptance artifact |
|---|---|---|---|---|---|
| YN ÖKC / GMP-3 protocol implementation | Turkish tax authority (GİB) / device manufacturer | Official GMP-3 protocol specification document | Any real `FiscalDevicePort` implementation beyond the honest `Unconfigured`/test-only adapters above | Obtain and review the official spec; do not infer command bytes from any third-party blog/forum source | A real-device transaction (sale + Z-report) accepted by GİB's own certification process |
| PAX A910SF SDK integration | PAX Technology | Official PAX SDK (native Android/iOS bindings) + integration guide | The device-communication transport layer `FiscalDevicePort.send` would call | Vendor documentation review + PAX-provided test/certification hardware | A real hardware acceptance test exercising sale/refund/cancellation/day-end against a physical A910SF unit |
| PAX/GMP-3 device provisioning & merchant credentials | Restaurant's own fiscal service provider / GİB-approved integrator | Provisioned device serial, merchant/terminal ids, any provider-issued keys | Any live transaction against a real device, even in a sandbox | Formal onboarding with a GİB-approved fiscal ÖKC provider | Provider-issued test credentials + a documented sandbox environment |
| Real PAX/GMP-3 SDK acceptance test suite | This project (once the above three are available) | The artifacts above | `PAX_A910SF_PRODUCTION_ADAPTER_COMPLETE=YES` / `GMP3_REAL_DEVICE_ACCEPTANCE_COMPLETE=YES` | N/A — cannot be written without the above | Full recovery-matrix test run against real hardware (timeout, duplicate response, device-disconnected, late-success, printer-unavailable-after-fiscal-success) |

**No workaround exists that safely closes this gap.** Building a fiscal adapter against an unofficial,
inferred, or reverse-engineered protocol description would risk real tax-compliance and financial-audit
consequences for the business — categorically out of scope for this codebase to attempt without the
official specification in hand.

## 3. Blocked acceptance tests (cannot be written or run in this environment)

- Real PAX A910SF sale/refund/cancellation/day-end transaction acceptance (requires physical hardware).
- Real GMP-3 protocol conformance test against GİB's own certification process.
- Device-disconnected / printer-unavailable-after-fiscal-success recovery against real hardware (the
  software-only equivalents — `FORCE_TIMEOUT`/`FORCE_UNAVAILABLE` markers on the deterministic test
  adapter — ARE implemented and tested; they prove the STATE MACHINE is correct, not that the real device
  behaves this way).
- Any claim of PAX/GMP-3 certification — per the governing instruction's own explicit rule, **a simulator
  passing this wave's tests is never real PAX/GMP-3 certification**, and none of this document's language
  should be read as implying otherwise.

## 4. Final tag consequence

`PAX_A910SF_PRODUCTION_ADAPTER_COMPLETE=NO`, `GMP3_REAL_DEVICE_ACCEPTANCE_COMPLETE=NO` — both are the
honest, structural consequence of the confirmed absence documented in §1, not an oversight or a deferred
task this wave failed to attempt. Every other AP-4 Wave C requirement not dependent on real vendor
hardware (journal, offline lease, durable outbox, state machine, tests) is real, wired, and tested — see
`docs/decisions.md` ADR-046 for the full closure record.
