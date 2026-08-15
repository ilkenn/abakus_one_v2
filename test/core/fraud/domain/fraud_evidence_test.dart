import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/core/fraud/domain/fraud_evidence.dart';
import 'package:abakus_one_v2/core/fraud/domain/fraud_evidence_availability.dart';
import 'package:abakus_one_v2/core/fraud/domain/fraud_evidence_kind.dart';
import 'package:abakus_one_v2/core/fraud/domain/mock_location_status.dart';
import 'package:flutter_test/flutter_test.dart';

ClientLocationEvidence _location({
  MockLocationStatus status = MockLocationStatus.notDetected,
}) {
  return ClientLocationEvidence(
    latitude: 41.0,
    longitude: 29.0,
    accuracyMeters: 12,
    clientCapturedAt: DateTime(2026, 8, 15, 10, 0),
    mockLocationStatus: status,
    permissionState: 'granted',
    precisionState: 'precise',
  );
}

void main() {
  group('FraudEvidence tenant-anchor invariant', () {
    test('pre-order evidence with all-null tenant fields is valid', () {
      final evidence = FraudEvidence(
        id: 'e1',
        kind: FraudEvidenceKind.addressSave,
        subjectUid: 'customer-1',
        clientLocation: _location(),
        availability: FraudEvidenceAvailability.available,
        serverReceivedAt: DateTime(2026, 8, 15, 10, 0, 1),
        createdAt: DateTime(2026, 8, 15, 10, 0, 2),
      );

      expect(evidence.organizationId, isNull);
      expect(evidence.branchId, isNull);
      expect(evidence.orderId, isNull);
      expect(evidence.isPreOrderEvidence, isTrue);
    });

    test('order evidence with all tenant fields populated is valid', () {
      final evidence = FraudEvidence(
        id: 'e2',
        kind: FraudEvidenceKind.orderSubmit,
        subjectUid: 'customer-1',
        clientLocation: _location(),
        availability: FraudEvidenceAvailability.available,
        serverReceivedAt: DateTime(2026, 8, 15, 10, 0, 1),
        createdAt: DateTime(2026, 8, 15, 10, 0, 2),
        organizationId: 'org-1',
        branchId: 'branch-1',
        orderId: 'order-1',
      );

      expect(evidence.isPreOrderEvidence, isFalse);
    });

    test('a partial tenant anchor (only organizationId) throws', () {
      expect(
        () => FraudEvidence(
          id: 'e3',
          kind: FraudEvidenceKind.orderSubmit,
          subjectUid: 'customer-1',
          clientLocation: _location(),
          availability: FraudEvidenceAvailability.available,
          serverReceivedAt: DateTime(2026, 8, 15, 10, 0, 1),
          createdAt: DateTime(2026, 8, 15, 10, 0, 2),
          organizationId: 'org-1',
        ),
        throwsA(isA<PartialFraudEvidenceTenantAnchorViolation>()),
      );
    });

    test('a partial tenant anchor (organizationId + branchId, no orderId) throws', () {
      expect(
        () => FraudEvidence(
          id: 'e4',
          kind: FraudEvidenceKind.orderSubmit,
          subjectUid: 'customer-1',
          clientLocation: _location(),
          availability: FraudEvidenceAvailability.available,
          serverReceivedAt: DateTime(2026, 8, 15, 10, 0, 1),
          createdAt: DateTime(2026, 8, 15, 10, 0, 2),
          organizationId: 'org-1',
          branchId: 'branch-1',
        ),
        throwsA(isA<PartialFraudEvidenceTenantAnchorViolation>()),
      );
    });

    test('a partial tenant anchor (only orderId) throws', () {
      expect(
        () => FraudEvidence(
          id: 'e5',
          kind: FraudEvidenceKind.orderSubmit,
          subjectUid: 'customer-1',
          clientLocation: _location(),
          availability: FraudEvidenceAvailability.available,
          serverReceivedAt: DateTime(2026, 8, 15, 10, 0, 1),
          createdAt: DateTime(2026, 8, 15, 10, 0, 2),
          orderId: 'order-1',
        ),
        throwsA(isA<PartialFraudEvidenceTenantAnchorViolation>()),
      );
    });
  });

  group('FraudEvidence availability/clientLocation invariant (FRAUD-F.1)', () {
    test('available with a non-null clientLocation is valid', () {
      final evidence = FraudEvidence(
        id: 'e9',
        kind: FraudEvidenceKind.addressSave,
        subjectUid: 'customer-1',
        clientLocation: _location(),
        availability: FraudEvidenceAvailability.available,
        serverReceivedAt: DateTime(2026, 8, 15, 10, 0, 1),
        createdAt: DateTime(2026, 8, 15, 10, 0, 2),
      );

      expect(evidence.availability, FraudEvidenceAvailability.available);
      expect(evidence.clientLocation, isNotNull);
    });

    test('unavailable with a null clientLocation and a reason is valid', () {
      final evidence = FraudEvidence(
        id: 'e10',
        kind: FraudEvidenceKind.addressSave,
        subjectUid: 'customer-1',
        availability: FraudEvidenceAvailability.unavailable,
        unavailableReason: 'permission_denied',
        serverReceivedAt: DateTime(2026, 8, 15, 10, 0, 1),
        createdAt: DateTime(2026, 8, 15, 10, 0, 2),
      );

      expect(evidence.clientLocation, isNull);
      expect(evidence.unavailableReason, 'permission_denied');
    });

    test('incomplete with a null clientLocation is valid', () {
      final evidence = FraudEvidence(
        id: 'e11',
        kind: FraudEvidenceKind.addressSave,
        subjectUid: 'customer-1',
        availability: FraudEvidenceAvailability.incomplete,
        serverReceivedAt: DateTime(2026, 8, 15, 10, 0, 1),
        createdAt: DateTime(2026, 8, 15, 10, 0, 2),
      );

      expect(evidence.clientLocation, isNull);
    });

    test('available with a null clientLocation throws', () {
      expect(
        () => FraudEvidence(
          id: 'e12',
          kind: FraudEvidenceKind.addressSave,
          subjectUid: 'customer-1',
          availability: FraudEvidenceAvailability.available,
          serverReceivedAt: DateTime(2026, 8, 15, 10, 0, 1),
          createdAt: DateTime(2026, 8, 15, 10, 0, 2),
        ),
        throwsA(isA<InconsistentFraudEvidenceAvailabilityViolation>()),
      );
    });

    test('unavailable with a non-null clientLocation throws', () {
      expect(
        () => FraudEvidence(
          id: 'e13',
          kind: FraudEvidenceKind.addressSave,
          subjectUid: 'customer-1',
          clientLocation: _location(),
          availability: FraudEvidenceAvailability.unavailable,
          serverReceivedAt: DateTime(2026, 8, 15, 10, 0, 1),
          createdAt: DateTime(2026, 8, 15, 10, 0, 2),
        ),
        throwsA(isA<InconsistentFraudEvidenceAvailabilityViolation>()),
      );
    });
  });

  group('FraudEvidence timestamp provenance', () {
    test('clientCapturedAt, serverReceivedAt, and createdAt are distinct, independently-settable fields', () {
      final clientCapturedAt = DateTime(2026, 8, 15, 9, 0);
      final serverReceivedAt = DateTime(2026, 8, 15, 9, 5);
      final createdAt = DateTime(2026, 8, 15, 9, 6);

      final evidence = FraudEvidence(
        id: 'e6',
        kind: FraudEvidenceKind.addressSave,
        subjectUid: 'customer-1',
        clientLocation: ClientLocationEvidence(
          latitude: 41.0,
          longitude: 29.0,
          accuracyMeters: 12,
          clientCapturedAt: clientCapturedAt,
          mockLocationStatus: MockLocationStatus.notDetected,
          permissionState: 'granted',
          precisionState: 'precise',
        ),
        availability: FraudEvidenceAvailability.available,
        serverReceivedAt: serverReceivedAt,
        createdAt: createdAt,
      );

      // A deliberately skewed clientCapturedAt (5 minutes before the
      // server ever saw the request) must be preserved as reported, never
      // silently reconciled against serverReceivedAt/createdAt — the
      // point of keeping the three fields separate.
      expect(evidence.clientLocation!.clientCapturedAt, clientCapturedAt);
      expect(evidence.serverReceivedAt, serverReceivedAt);
      expect(evidence.createdAt, createdAt);
      expect(evidence.clientLocation!.clientCapturedAt,
          isNot(evidence.serverReceivedAt));
    });
  });

  group('MockLocationStatus semantics', () {
    test('all four values exist', () {
      expect(MockLocationStatus.values, hasLength(4));
      expect(MockLocationStatus.values, contains(MockLocationStatus.detected));
      expect(
          MockLocationStatus.values, contains(MockLocationStatus.notDetected));
      expect(
          MockLocationStatus.values, contains(MockLocationStatus.unsupported));
      expect(
          MockLocationStatus.values, contains(MockLocationStatus.unavailable));
    });

    test('notDetected is stored and read back exactly as notDetected, never coerced to a boolean "genuine" concept', () {
      final evidence = FraudEvidence(
        id: 'e7',
        kind: FraudEvidenceKind.addressSave,
        subjectUid: 'customer-1',
        clientLocation: _location(status: MockLocationStatus.notDetected),
        availability: FraudEvidenceAvailability.available,
        serverReceivedAt: DateTime(2026, 8, 15, 10, 0, 1),
        createdAt: DateTime(2026, 8, 15, 10, 0, 2),
      );

      expect(evidence.clientLocation!.mockLocationStatus,
          MockLocationStatus.notDetected);
    });
  });

  group('ServerFraudInterpretation', () {
    test('defaults to all-null/unpopulated fields — nothing fabricated', () {
      final evidence = FraudEvidence(
        id: 'e8',
        kind: FraudEvidenceKind.addressSave,
        subjectUid: 'customer-1',
        clientLocation: _location(),
        availability: FraudEvidenceAvailability.available,
        serverReceivedAt: DateTime(2026, 8, 15, 10, 0, 1),
        createdAt: DateTime(2026, 8, 15, 10, 0, 2),
      );

      expect(evidence.interpretation.distanceMeters, isNull);
      expect(evidence.interpretation.buildingNumber, isNull);
      expect(evidence.interpretation.appCheckState, isNull);
      expect(evidence.interpretation.policyVersion, isNull);
    });
  });
}
