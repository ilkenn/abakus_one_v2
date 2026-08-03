import 'package:abakus_one_v2/features/smart_import/application/use_cases/normalize_and_analyze_parsed_menu.dart';
import 'package:abakus_one_v2/features/smart_import/domain/import_confidence.dart';
import 'package:abakus_one_v2/features/smart_import/domain/parsed_category.dart';
import 'package:abakus_one_v2/features/smart_import/domain/parsed_menu.dart';
import 'package:abakus_one_v2/features/smart_import/domain/parsed_product.dart';
import 'package:flutter_test/flutter_test.dart';

ParsedProduct _product({
  required String tempId,
  required String name,
  required String categoryTempId,
  double? price,
  String? description,
  String? currencyCode,
}) {
  return ParsedProduct(
    tempId: tempId,
    categoryTempId: categoryTempId,
    name: name,
    description: description,
    price: price,
    currencyCode: currencyCode,
    confidence: const ImportConfidence(
        satisfiedEvidenceCount: 2, totalEvidenceCount: 4),
  );
}

void main() {
  const useCase = NormalizeAndAnalyzeParsedMenu();

  test('flags duplicate categories by normalized name', () {
    const menu = ParsedMenu(categories: [
      ParsedCategory(tempId: 'c1', name: 'Bowl'),
      ParsedCategory(tempId: 'c2', name: '  bowl  '),
    ]);

    final result = useCase(menu);

    expect(result.issues.any((i) => i.code == 'duplicate_category'), isTrue);
  });

  test('flags the same product appearing under different categories', () {
    final menu = ParsedMenu(products: [
      _product(tempId: 'p1', name: 'Ayran', categoryTempId: 'c1', price: 25),
      _product(tempId: 'p2', name: 'Ayran', categoryTempId: 'c2', price: 25),
    ]);

    final result = useCase(menu);

    expect(
      result.issues.any((i) => i.code == 'product_in_multiple_categories'),
      isTrue,
    );
  });

  test('flags conflicting prices for the same normalized product name', () {
    final menu = ParsedMenu(products: [
      _product(tempId: 'p1', name: 'Ayran', categoryTempId: 'c1', price: 25),
      _product(tempId: 'p2', name: 'Ayran', categoryTempId: 'c1', price: 30),
    ]);

    final result = useCase(menu);

    expect(result.issues.any((i) => i.code == 'conflicting_price'), isTrue);
  });

  test('flags a missing price as an error-level issue', () {
    final menu = ParsedMenu(products: [
      _product(tempId: 'p1', name: 'Ürün', categoryTempId: 'c1'),
    ]);

    final result = useCase(menu);

    expect(
      result.issues.any((i) => i.code == 'invalid_price_format'),
      isTrue,
    );
  });

  test('flags an invalid currency code', () {
    final menu = ParsedMenu(products: [
      _product(
        tempId: 'p1',
        name: 'Ürün',
        categoryTempId: 'c1',
        price: 100,
        currencyCode: 'XYZ',
      ),
    ]);

    final result = useCase(menu);

    expect(result.issues.any((i) => i.code == 'invalid_currency'), isTrue);
  });

  test('flags a description containing embedded-modifier keywords', () {
    final menu = ParsedMenu(products: [
      _product(
        tempId: 'p1',
        name: 'Pizza',
        categoryTempId: 'c1',
        price: 150,
        description: 'Küçük, orta veya büyük boyut seçilebilir',
      ),
    ]);

    final result = useCase(menu);

    expect(
      result.issues.any((i) => i.code == 'possible_embedded_modifier_group'),
      isTrue,
    );
  });

  test('never merges or removes parsed records — same counts in and out', () {
    final menu = ParsedMenu(
      categories: const [
        ParsedCategory(tempId: 'c1', name: 'Bowl'),
        ParsedCategory(tempId: 'c2', name: 'Bowl'),
      ],
      products: [
        _product(tempId: 'p1', name: 'Ayran', categoryTempId: 'c1', price: 25),
        _product(tempId: 'p2', name: 'Ayran', categoryTempId: 'c1', price: 30),
      ],
    );

    final result = useCase(menu);

    expect(result.categories, hasLength(2));
    expect(result.products, hasLength(2));
  });
}
