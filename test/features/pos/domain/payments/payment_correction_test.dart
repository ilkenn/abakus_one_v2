import 'package:abakus_one_v2/features/payment/domain/models/payment_method_seed_data.dart';
import 'package:abakus_one_v2/features/payment/domain/models/payment_method_snapshot.dart';
import 'package:abakus_one_v2/features/pos/domain/payments/payment_correction.dart';
import 'package:abakus_one_v2/features/pos/domain/payments/payment_correction_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PaymentCorrection — paymentMethodCorrection', () {
    test(
        'links the original split to its replacement with before/after method snapshots',
        () {
      final correction = PaymentCorrection(
        id: 'corr-1',
        correctionType: PaymentCorrectionType.paymentMethodCorrection,
        originalPaymentId: 'split-1',
        replacementPaymentId: 'split-2',
        correctionReferenceId: 'ref-1',
        previousPaymentMethodSnapshot:
            PaymentMethodSnapshot.capture(PaymentMethodSeedData.cash),
        newPaymentMethodSnapshot:
            PaymentMethodSnapshot.capture(PaymentMethodSeedData.creditCard),
        correctionReason: 'Cashier entered cash instead of card',
        correctedByStaffId: 'staff-1',
        correctedAt: DateTime(2026, 7, 29),
      );

      expect(correction.originalPaymentId, 'split-1');
      expect(correction.replacementPaymentId, 'split-2');
      expect(correction.previousPaymentMethodSnapshot!.paymentMethodId, 'cash');
      expect(
          correction.newPaymentMethodSnapshot!.paymentMethodId, 'credit_card');
    });

    test('replacementPaymentId is nullable until the replacement split exists',
        () {
      final correction = PaymentCorrection(
        id: 'corr-1',
        correctionType: PaymentCorrectionType.paymentMethodCorrection,
        originalPaymentId: 'split-1',
        correctionReferenceId: 'ref-1',
        correctionReason: 'Pending replacement',
        correctedByStaffId: 'staff-1',
        correctedAt: DateTime(2026, 7, 29),
      );

      expect(correction.replacementPaymentId, isNull);
    });
  });
}
