import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/home/presentation/screens/home_screen.dart';
import 'package:abakus_one_v2/features/home/presentation/widgets/popular_products_section.dart';
import 'package:abakus_one_v2/features/menu/presentation/screens/product_detail_screen.dart';

void main() {
  testWidgets(
    'Populer Urunler karti Material ink-splash assertion firlatmadan render edilir ve urun detayina gecer',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final sectionTitle = find.text('En Sevilen Bowl\'lar');
      await tester.dragUntilVisible(
        sectionTitle,
        find.byType(Scrollable).first,
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();

      final firstCard = find
          .descendant(
            of: find.byType(PopularProductsSection),
            matching: find.byType(InkWell),
          )
          .first;
      await tester.ensureVisible(firstCard);
      await tester.pumpAndSettle();

      await tester.tap(firstCard);
      await tester.pumpAndSettle();

      expect(find.byType(ProductDetailScreen), findsOneWidget);
    },
  );
}
