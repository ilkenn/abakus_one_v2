import 'package:abakus_one_v2/core/fraud/domain/fraud_risk_context.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FraudRiskContext', () {
    test('constructs immutably with references to its evidence/signals', () {
      final context = FraudRiskContext(
        id: 'ctx-1',
        orderId: 'order-1',
        evidenceIds: const ['evidence-1', 'evidence-2'],
        signalIds: const ['signal-1'],
        priorEvidenceId: 'evidence-0',
        policyVersion: 'unversioned-f0',
        createdAt: DateTime(2026, 8, 15, 11, 0),
      );

      expect(context.orderId, 'order-1');
      expect(context.evidenceIds, ['evidence-1', 'evidence-2']);
      expect(context.priorEvidenceId, 'evidence-0');
    });

    test('priorEvidenceId is optional — null when no address-save evidence exists for this order', () {
      final context = FraudRiskContext(
        id: 'ctx-2',
        orderId: 'order-2',
        evidenceIds: const ['evidence-3'],
        signalIds: const [],
        policyVersion: 'unversioned-f0',
        createdAt: DateTime(2026, 8, 15, 11, 0),
      );

      expect(context.priorEvidenceId, isNull);
    });
  });
}
