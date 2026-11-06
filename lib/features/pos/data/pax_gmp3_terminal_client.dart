/// How a [PaxGmp3TerminalClient.collectPayment] attempt ended. Mirrors the
/// shape every other "unknown outcome must never be silently treated as
/// success/failure" boundary in this codebase already uses (e.g.
/// `PaymentAttemptStatus`'s own locked `timedOut` handling,
/// `docs/payment_cash_fiscal_architecture.md` §8/§14) — [timedOut] and
/// [unavailable] are both distinct from [declined]: neither one means "the
/// terminal said no," so neither may ever be shown to the cashier as a
/// decline.
enum PaxTerminalOutcome {
  /// The terminal reported a successful card presentment — mirrors the
  /// GMP-3/ECR '00' response code the operator's own instructions
  /// describe. **Never produced by [UnavailablePaxGmp3TerminalClient]** —
  /// there is no path to this outcome anywhere in this codebase today.
  approved,

  /// The terminal reported a definitive rejection (card declined, wrong
  /// PIN, insufficient funds, etc.) — a real, final "no," never confused
  /// with [timedOut]/[unavailable].
  declined,

  /// No definitive response arrived within the expected window — the
  /// cashier must reconcile against the physical terminal's own screen/
  /// receipt before retrying, exactly like every other `timedOut`
  /// boundary in this codebase (never silently retried, never shown as
  /// either success or failure).
  timedOut,

  /// The cashier cancelled from the "kart bekleniyor" modal before any
  /// response arrived.
  cancelled,

  /// No real device-communication layer exists yet — see
  /// [UnavailablePaxGmp3TerminalClient]'s own doc comment for why.
  unavailable,
}

class PaxTerminalResult {
  const PaxTerminalResult({
    required this.outcome,
    this.authCode,
    this.rrn,
    this.message,
  });

  final PaxTerminalOutcome outcome;

  /// The terminal's own authorization code — `null` unless [outcome] is
  /// [PaxTerminalOutcome.approved].
  final String? authCode;

  /// The terminal's own Retrieval Reference Number — `null` unless
  /// [outcome] is [PaxTerminalOutcome.approved].
  final String? rrn;

  /// A human-readable Turkish message for the cashier — always present
  /// for [PaxTerminalOutcome.declined]/[PaxTerminalOutcome.unavailable],
  /// optional otherwise.
  final String? message;
}

/// The physical PAX A910SF terminal, reached directly over the branch's
/// own local network (a generic ECR/GMP-3 TCP socket to the device's own
/// IP — never through any Cloud Function, since a terminal on a
/// restaurant's LAN is not reachable from Firebase's own servers). Mirrors
/// `RawPrinterAdapter`'s own "physical LAN/USB hardware boundary, not a
/// cloud service" shape.
///
/// **Deliberately still a stub** (2026-11-06) — `docs
/// /payment_cash_fiscal_architecture.md` §14/§21/§22 and `docs/decisions
/// .md` ADR-032 lock YN ÖKC/GMP-3/PAX A910SF as a
/// `CONTROLLED_EXTERNAL_DEPENDENCY`: "no vendor protocol detail is
/// written without official vendor documentation," and real-hardware
/// acceptance testing is a hard gate before any production transaction.
/// No official PAX SDK/GMP-3 protocol specification has been supplied —
/// inventing the wire format here would mean shipping code that either
/// fails against the real terminal or, worse, silently misreads its
/// response for something that moves money. This interface/settings/UI
/// boundary exists so the real implementation has a working seam to plug
/// into later, without any caller-facing shape change — the same
/// "everything buildable without real vendor access, nothing invented"
/// split this codebase's AP-4 payment/fiscal waves already established
/// (see `docs/decisions.md` ADR-046).
abstract interface class PaxGmp3TerminalClient {
  Future<PaxTerminalResult> collectPayment({
    required int amountMinorUnits,
    required String currencyCode,
    required String idempotencyKey,
  });
}

class UnavailablePaxGmp3TerminalClient implements PaxGmp3TerminalClient {
  const UnavailablePaxGmp3TerminalClient();

  @override
  Future<PaxTerminalResult> collectPayment({
    required int amountMinorUnits,
    required String currencyCode,
    required String idempotencyKey,
  }) async {
    return const PaxTerminalResult(
      outcome: PaxTerminalOutcome.unavailable,
      message: 'PAX A910SF / GMP-3 entegrasyonu henüz yapılandırılmadı.',
    );
  }
}
