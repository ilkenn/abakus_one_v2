import 'package:abakus_one_v2/features/pos/domain/payments/payment_void.dart';
import 'package:abakus_one_v2/features/pos/domain/payments/payment_void_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PaymentVoid', () {
    test('starts pending and carries the required fields', () {
      final void_ = PaymentVoid(
        id: 'v1',
        originalSplitId: 'split-1',
        reason: 'Wrong method selected',
        requestedByStaffId: 'staff-1',
        requestedAt: DateTime(2026, 7, 29),
        status: PaymentVoidStatus.pending,
      );

      expect(void_.status, PaymentVoidStatus.pending);
      expect(void_.providerReversalReference, isNull);
    });

    test('copyWith moves to completed with a provider reversal reference', () {
      final void_ = PaymentVoid(
        id: 'v1',
        originalSplitId: 'split-1',
        reason: 'Wrong method selected',
        requestedByStaffId: 'staff-1',
        requestedAt: DateTime(2026, 7, 29),
        status: PaymentVoidStatus.pending,
      );

      final completed = void_.copyWith(
        status: PaymentVoidStatus.completed,
        providerReversalReference: 'REV-123',
      );

      expect(completed.status, PaymentVoidStatus.completed);
      expect(completed.providerReversalReference, 'REV-123');
      // Original is untouched — copyWith never mutates in place.
      expect(void_.status, PaymentVoidStatus.pending);
    });

    test('copyWith to rejected requires no provider reference', () {
      final void_ = PaymentVoid(
        id: 'v1',
        originalSplitId: 'split-1',
        reason: 'Wrong method selected',
        requestedByStaffId: 'staff-1',
        requestedAt: DateTime(2026, 7, 29),
        status: PaymentVoidStatus.pending,
      );

      final rejected = void_.copyWith(status: PaymentVoidStatus.rejected);

      expect(rejected.status, PaymentVoidStatus.rejected);
      expect(rejected.providerReversalReference, isNull);
    });
  });
}
