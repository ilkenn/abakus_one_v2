import 'package:abakus_one_v2/features/smart_import/domain/parsing/csv_menu_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CsvMenuParser', () {
    const parser = CsvMenuParser();

    test('parses categories and products from a well-formed CSV', () {
      const csv = 'category,name,description,price,currency\n'
          'Bowl,Tavuklu Bowl,Izgara tavuk ile,189.90,TRY\n'
          'Bowl,Somonlu Bowl,Taze somon ile,219.90,TRY\n'
          'İçecek,Ayran,,25.00,TRY\n';

      final menu = parser.parse(csv);

      expect(menu.categories.map((c) => c.name), ['Bowl', 'İçecek']);
      expect(menu.products, hasLength(3));
      expect(menu.products.first.name, 'Tavuklu Bowl');
      expect(menu.products.first.price, 189.90);
    });

    test('skips a row missing a required field', () {
      const csv = 'category,name,price\n'
          'Bowl,,150\n' // missing name
          'Bowl,Valid Ürün,150\n';

      final menu = parser.parse(csv);

      expect(menu.products, hasLength(1));
      expect(menu.products.single.name, 'Valid Ürün');
    });

    test('an unparseable price yields a null price, not a fabricated one', () {
      const csv = 'category,name,price\nBowl,Ürün,not-a-number\n';

      final menu = parser.parse(csv);

      expect(menu.products.single.price, isNull);
    });

    test('confidence score reflects only real evidence found', () {
      const csv = 'category,name,description,price\n'
          'Bowl,Tam Ürün,Açıklama var,150\n'
          'Bowl,Eksik Ürün,,not-a-number\n';

      final menu = parser.parse(csv);

      final full = menu.products.firstWhere((p) => p.name == 'Tam Ürün');
      final partial = menu.products.firstWhere((p) => p.name == 'Eksik Ürün');

      expect(full.confidence.score, 100);
      expect(partial.confidence.score, lessThan(full.confidence.score));
    });

    test('empty input produces an empty menu', () {
      final menu = parser.parse('');

      expect(menu.categories, isEmpty);
      expect(menu.products, isEmpty);
    });
  });
}
