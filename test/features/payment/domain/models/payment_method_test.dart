import 'package:abakus_one_v2/features/payment/domain/models/payment_method.dart';
import 'package:abakus_one_v2/features/payment/domain/models/payment_method_reporting_category.dart';
import 'package:abakus_one_v2/features/payment/domain/models/payment_provider_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PaymentMethod', () {
    test('equality is based on id only, like Currency', () {
      const a = PaymentMethod(
        id: 'x',
        name: 'A',
        iconAssetPath: 'a.png',
        brandColorValue: 0xFF000000,
        isActive: true,
        supportsSplitPayment: true,
        supportsRefund: true,
        requiresReferenceNumber: false,
        requiresApproval: false,
        sortOrder: 0,
        reportingCategory: PaymentMethodReportingCategory.cash,
      );
      const b = PaymentMethod(
        id: 'x',
        name: 'Different name',
        iconAssetPath: 'b.png',
        brandColorValue: 0xFFFFFFFF,
        isActive: false,
        supportsSplitPayment: false,
        supportsRefund: false,
        requiresReferenceNumber: true,
        requiresApproval: true,
        sortOrder: 5,
        reportingCategory: PaymentMethodReportingCategory.card,
      );

      expect(a, b);
    });

    test('requiresProvider reflects whether providerId is set', () {
      const manual = PaymentMethod(
        id: 'cash',
        name: 'Cash',
        iconAssetPath: 'cash.png',
        brandColorValue: 0xFF000000,
        isActive: true,
        supportsSplitPayment: true,
        supportsRefund: true,
        requiresReferenceNumber: false,
        requiresApproval: false,
        sortOrder: 0,
        reportingCategory: PaymentMethodReportingCategory.cash,
      );
      const processed = PaymentMethod(
        id: 'pluxee',
        name: 'Pluxee',
        iconAssetPath: 'pluxee.png',
        brandColorValue: 0xFF000000,
        isActive: true,
        supportsSplitPayment: true,
        supportsRefund: true,
        requiresReferenceNumber: false,
        requiresApproval: false,
        sortOrder: 1,
        reportingCategory: PaymentMethodReportingCategory.mealCard,
        providerId: PaymentProviderId.pluxee,
      );

      expect(manual.requiresProvider, isFalse);
      expect(processed.requiresProvider, isTrue);
    });
  });
}
