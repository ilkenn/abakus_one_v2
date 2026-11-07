import 'package:abakus_one_v2/features/pos/data/scale_reader_port.dart';
import 'package:flutter_test/flutter_test.dart';

/// Adım 4 (2026-11-07) — same "no real transport yet, never silently
/// invented" reasoning as `UnavailablePaxGmp3TerminalClient`'s own tests.
void main() {
  test(
      'UnavailableScaleReaderPort always resolves unavailable with a '
      'Turkish, staff-facing message — never a fabricated reading', () async {
    const port = UnavailableScaleReaderPort();

    final reading = await port.readWeightGrams();

    expect(reading.outcome, ScaleReadingOutcome.unavailable);
    expect(reading.grams, isNull);
    expect(reading.message, isNotNull);
  });
}
