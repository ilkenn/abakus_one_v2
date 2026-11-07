/// How a [ScaleReaderPort.readWeightGrams] attempt ended — mirrors
/// `PaxTerminalOutcome`'s own shape: [unavailable] is never confused with a
/// real reading, so no caller can mistake "no scale connected" for "the
/// scale reported zero grams."
enum ScaleReadingOutcome {
  /// The scale reported a stable weight — never produced by
  /// [UnavailableScaleReaderPort]; there is no real serial-port transport
  /// yet.
  read,

  /// No real serial-port scale transport exists yet — see
  /// [UnavailableScaleReaderPort]'s own doc comment.
  unavailable,
}

class ScaleReading {
  const ScaleReading({required this.outcome, this.grams, this.message});

  final ScaleReadingOutcome outcome;

  /// The read weight in whole grams — `null` unless [outcome] is
  /// [ScaleReadingOutcome.read].
  final int? grams;

  /// A human-readable Turkish message for the cashier — always present for
  /// [ScaleReadingOutcome.unavailable].
  final String? message;
}

/// A branch-local serial-port scale, read directly (never through a Cloud
/// Function — a scale on a till's own serial/USB port is not reachable
/// from Firebase's servers) — mirrors [PaxGmp3TerminalClient]'s own
/// "physical hardware boundary" shape.
///
/// **Deliberately still a stub** (Adım 4, 2026-11-07) — same reasoning as
/// [UnavailablePaxGmp3TerminalClient]: no real scale model/serial protocol
/// has been specified yet, so inventing a wire format here would mean
/// shipping code that either fails against the real device or silently
/// misreads its weight. This interface exists so a real implementation has
/// a working seam to plug into later; [WeightEntryDialog]'s manual gram
/// entry is the only path staff have until then.
abstract interface class ScaleReaderPort {
  Future<ScaleReading> readWeightGrams();
}

class UnavailableScaleReaderPort implements ScaleReaderPort {
  const UnavailableScaleReaderPort();

  @override
  Future<ScaleReading> readWeightGrams() async {
    return const ScaleReading(
      outcome: ScaleReadingOutcome.unavailable,
      message: 'Bağlı seri port terazi bulunamadı. Lütfen gramajı elle girin.',
    );
  }
}
