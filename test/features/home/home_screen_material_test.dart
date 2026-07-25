import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/home/presentation/screens/home_screen.dart';
import 'package:abakus_one_v2/features/menu/presentation/screens/product_detail_screen.dart';

void main() {
  testWidgets(
    'Populer Urunler listesi Material ink-splash assertion firlatmadan render edilir ve urun detayina gecer',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final firstPopularProduct = find.text('Popüler Ürünler');
      await tester.ensureVisible(firstPopularProduct);
      await tester.pumpAndSettle();

      final firstListTile = find.byType(ListTile).first;
      await tester.ensureVisible(firstListTile);
      await tester.pumpAndSettle();

      await tester.tap(firstListTile);
      await tester.pumpAndSettle();

      expect(find.byType(ProductDetailScreen), findsOneWidget);
    },
  );
}
