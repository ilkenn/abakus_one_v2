import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/orders/domain/models/dine_in_line_status.dart';

void main() {
  group('dineInLineStatusFromWire', () {
    test('parses every status the server writes', () {
      expect(dineInLineStatusFromWire('pendingApproval'),
          DineInLineStatus.pendingApproval);
      expect(dineInLineStatusFromWire('accepted'), DineInLineStatus.accepted);
      expect(dineInLineStatusFromWire(null), DineInLineStatus.accepted);
      expect(dineInLineStatusFromWire('rejected'), DineInLineStatus.rejected);
      expect(dineInLineStatusFromWire('proposedChange'),
          DineInLineStatus.proposedChange);
      // 2026-11-10 — written by functions/src/checkFinancialAdjustments.ts
      // (manager-approved cancellation of an accepted line); its absence
      // broke Admin Siparişler and the KDS board for every such order.
      expect(dineInLineStatusFromWire('cancelledAfterAcceptance'),
          DineInLineStatus.cancelledAfterAcceptance);
    });

    test('round-trips through the wire name', () {
      for (final status in DineInLineStatus.values) {
        expect(
            dineInLineStatusFromWire(dineInLineStatusToWire(status)), status);
      }
    });

    test('still rejects a genuinely unknown value', () {
      expect(() => dineInLineStatusFromWire('somethingNew'),
          throwsA(isA<StateError>()));
    });
  });
}
