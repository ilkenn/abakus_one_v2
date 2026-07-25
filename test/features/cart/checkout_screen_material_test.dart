import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/cart/presentation/screens/checkout_screen.dart';

void main() {
  testWidgets(
    'CheckoutScreen radio/switch bolumleri Material ink-splash assertion firlatmadan render edilir',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: CheckoutScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Teslimat Zamani bolumu (ekranin en ustunde, ek scroll gerekmez).
      expect(find.text('Hemen (Mümkün olan en kısa sürede)'), findsOneWidget);

      // Geri kalan bolumleri gorunur hale getirmek icin listeyi kaydir.
      final scrollable = find
          .descendant(
            of: find.byType(CheckoutScreen),
            matching: find.byType(Scrollable),
          )
          .first;

      await tester.dragUntilVisible(
        find.text('Peçete, çatal ve bıçak istiyorum'),
        scrollable,
        const Offset(0, -300),
      );
      expect(find.text('Peçete, çatal ve bıçak istiyorum'), findsOneWidget);

      await tester.dragUntilVisible(
        find.text('Online Kredi/Banka Kartı'),
        scrollable,
        const Offset(0, -300),
      );
      expect(find.text('Online Kredi/Banka Kartı'), findsOneWidget);

      await tester.dragUntilVisible(
        find.text('Zil çalınsın'),
        scrollable,
        const Offset(0, -300),
      );
      expect(find.text('Zil çalınsın'), findsOneWidget);
      expect(find.text('Kapıya bırak'), findsOneWidget);
    },
  );
}
