import 'package:abakus_one_v2/core/fraud/domain/fraud_evidence_retention_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FraudEvidenceRetentionPolicy', () {
    test('computeExpiresAt adds retentionDuration to the given instant', () {
      const policy = FraudEvidenceRetentionPolicy(
        id: 'test-policy',
        retentionDuration: Duration(days: 1),
      );
      final from = DateTime(2026, 1, 1);

      expect(policy.computeExpiresAt(from), DateTime(2026, 1, 2));
    });

    test('legalBasisVersion defaults to null — no fabricated legal basis', () {
      const policy = FraudEvidenceRetentionPolicy(
        id: 'test-policy',
        retentionDuration: Duration(hours: 1),
      );

      expect(policy.legalBasisVersion, isNull);
    });

    test('a real legal basis version can be attached once one exists', () {
      const policy = FraudEvidenceRetentionPolicy(
        id: 'kvkk-approved',
        retentionDuration: Duration(days: 30),
        legalBasisVersion: 'kvkk-v1',
      );

      expect(policy.legalBasisVersion, 'kvkk-v1');
    });
  });
}
