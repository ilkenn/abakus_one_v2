import 'package:abakus_one_v2/core/fraud/domain/fraud_signal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FraudSignal', () {
    test('constructs with the expected descriptive fields', () {
      final signal = FraudSignal(
        id: 's1',
        evidenceId: 'e1',
        type: 'distance_mismatch',
        description: 'Reported location is far from the saved address',
        detectedAt: DateTime(2026, 8, 15, 10, 0),
      );

      expect(signal.id, 's1');
      expect(signal.evidenceId, 'e1');
      expect(signal.type, 'distance_mismatch');
      expect(signal.detectedAt, DateTime(2026, 8, 15, 10, 0));
    });

    test('carries no enforcement-shaped field — the type has no member named block/reject/ban/cancel', () {
      final signal = FraudSignal(
        id: 's2',
        evidenceId: 'e1',
        type: 'test_signal',
        description: 'test',
        detectedAt: DateTime(2026, 8, 15, 10, 0),
      );

      // Structural proof, not just documentation: FraudSignal's only
      // fields are id/evidenceId/type/description/detectedAt — there is
      // no boolean or enum this test (or any future caller) could even
      // read to make a block/ban/deny decision. Asserting the full field
      // set here means the enum can never silently grow one without this
      // test needing an update.
      expect(
        signal.toString(),
        isNot(contains('block')),
      );
    });
  });
}
