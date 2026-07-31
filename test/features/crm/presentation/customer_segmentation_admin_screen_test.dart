import 'package:abakus_one_v2/features/crm/presentation/screens/customer_segmentation_admin_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows an empty state with no registered customers',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: CustomerSegmentationAdminScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Kayıtlı müşteri bulunamadı.'), findsOneWidget);
    expect(find.text('Tümü'), findsWidgets);
  });
}
