import 'package:abakus_one_v2/features/payment/domain/models/payment_method.dart';
import 'package:abakus_one_v2/features/payment/domain/models/payment_method_reporting_category.dart';
import 'package:abakus_one_v2/features/payment/domain/models/payment_method_seed_data.dart';
import 'package:abakus_one_v2/features/payment/domain/models/payment_method_snapshot.dart';
import 'package:abakus_one_v2/features/payment/domain/models/payment_provider_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PaymentMethodSnapshot.capture', () {
    test('freezes every field off the live PaymentMethod', () {
      final snapshot =
          PaymentMethodSnapshot.capture(PaymentMethodSeedData.pluxee);

      expect(snapshot.paymentMethodId, 'pluxee');
      expect(snapshot.displayName, 'Pluxee');
      expect(
          snapshot.reportingCategory, PaymentMethodReportingCategory.mealCard);
      expect(snapshot.providerId, PaymentMethodSeedData.pluxee.providerId);
      expect(snapshot.supportsRefundAtCapture, isTrue);
    });

    test('captures optional terminal/provider fields when given', () {
      final snapshot = PaymentMethodSnapshot.capture(
        PaymentMethodSeedData.pluxee,
        transactionReference: 'txn-1',
        authorizationCode: 'auth-1',
        terminalId: 'terminal-1',
      );

      expect(snapshot.transactionReference, 'txn-1');
      expect(snapshot.authorizationCode, 'auth-1');
      expect(snapshot.terminalId, 'terminal-1');
    });

    test(
        'a later mutation to a differently-constructed PaymentMethod of the same id never affects an already-captured snapshot',
        () {
      const originalLikePluxee = PaymentMethod(
        id: 'pluxee',
        name: 'Pluxee',
        iconAssetPath: 'assets/images/payment/pluxee.png',
        brandColorValue: 0xFFEE2A7B,
        isActive: true,
        supportsSplitPayment: true,
        supportsRefund: true,
        requiresReferenceNumber: false,
        requiresApproval: false,
        sortOrder: 2,
        reportingCategory: PaymentMethodReportingCategory.mealCard,
        providerId: PaymentProviderId.pluxee,
      );
      final snapshot = PaymentMethodSnapshot.capture(originalLikePluxee);

      // Simulates an Admin Panel edit: renamed, refund disabled.
      const editedPluxee = PaymentMethod(
        id: 'pluxee',
        name: 'Pluxee (Yeniden Adlandırıldı)',
        iconAssetPath: 'assets/images/payment/pluxee_v2.png',
        brandColorValue: 0xFF000000,
        isActive: true,
        supportsSplitPayment: true,
        supportsRefund: false,
        requiresReferenceNumber: false,
        requiresApproval: false,
        sortOrder: 2,
        reportingCategory: PaymentMethodReportingCategory.mealCard,
      );

      expect(snapshot.displayName, 'Pluxee');
      expect(snapshot.supportsRefundAtCapture, isTrue);
      // The edited catalog entry is a distinct object; the frozen snapshot
      // never reads from it.
      expect(editedPluxee.name, isNot(snapshot.displayName));
    });
  });
}
