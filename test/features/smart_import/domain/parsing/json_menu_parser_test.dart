import 'package:abakus_one_v2/features/smart_import/domain/import_issue.dart';
import 'package:abakus_one_v2/features/smart_import/domain/parsing/json_menu_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('JsonMenuParser', () {
    const parser = JsonMenuParser();

    test('parses categories and products from well-formed JSON', () {
      const json = '''
      {
        "categories": [{"name": "Bowl"}],
        "products": [
          {"category": "Bowl", "name": "Tavuklu Bowl",
           "description": "Izgara tavuk", "price": 189.9, "currency": "TRY"}
        ]
      }
      ''';

      final menu = parser.parse(json);

      expect(menu.categories.map((c) => c.name), ['Bowl']);
      expect(menu.products, hasLength(1));
      expect(menu.products.single.price, 189.9);
    });

    test('a malformed JSON document yields an error issue, not a throw', () {
      final menu = parser.parse('{not valid json');

      expect(menu.products, isEmpty);
      expect(
        menu.issues.any((i) => i.severity == ImportIssueSeverity.error),
        isTrue,
      );
    });

    test('a non-object root yields an error issue', () {
      final menu = parser.parse('[1, 2, 3]');

      expect(
        menu.issues.any((i) => i.code == 'invalid_json_root'),
        isTrue,
      );
    });

    test('a product missing a category is skipped, not fabricated', () {
      const json = '''
      {"products": [{"name": "Ürün", "price": 100}]}
      ''';

      final menu = parser.parse(json);

      expect(menu.products, isEmpty);
    });
  });
}
