import 'package:abakus_one_v2/shared/widgets/images/payment_method_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('falls back to a brand-tinted icon when the asset does not exist',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: PaymentMethodLogo(
              iconAssetPath: 'assets/images/payment/nonexistent.png',
              brandColorValue: 0xFFEE2A7B,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.payments_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
