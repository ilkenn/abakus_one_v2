import '../import_confidence.dart';
import '../parsed_category.dart';
import '../parsed_menu.dart';
import '../parsed_product.dart';

/// Deterministic, dependency-free CSV parser — Phase 7
/// (`docs/decisions.md` ADR-024). No `csv` package exists in
/// `pubspec.yaml`; this hand-rolled reader is intentionally minimal:
/// comma-delimited, one header row, no quoted-field-with-embedded-comma
/// support (an honest, documented limitation, not a silent
/// mis-parse) — "provide deterministic local parsing for supported
/// structured formats" without adding a new dependency.
///
/// Expected header (case-insensitive, in any column order):
/// `category,name,description,price,currency`. `description`/`currency`
/// are optional columns; `category`/`name`/`price` are not — a row
/// missing any of those three is skipped and does not appear in the
/// result (no partial/guessed product is ever fabricated).
class CsvMenuParser {
  const CsvMenuParser();

  ParsedMenu parse(String rawCsv) {
    final lines = rawCsv
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) return const ParsedMenu();

    final header =
        lines.first.split(',').map((h) => h.trim().toLowerCase()).toList();
    final categoryIndex = header.indexOf('category');
    final nameIndex = header.indexOf('name');
    final descriptionIndex = header.indexOf('description');
    final priceIndex = header.indexOf('price');
    final currencyIndex = header.indexOf('currency');

    final categoriesByName = <String, ParsedCategory>{};
    final products = <ParsedProduct>[];
    var rowNumber = 1;

    for (final line in lines.skip(1)) {
      rowNumber++;
      final cells = line.split(',').map((c) => c.trim()).toList();
      if (categoryIndex == -1 ||
          nameIndex == -1 ||
          priceIndex == -1 ||
          categoryIndex >= cells.length ||
          nameIndex >= cells.length ||
          priceIndex >= cells.length) {
        continue;
      }

      final categoryName = cells[categoryIndex];
      final name = cells[nameIndex];
      final priceText = cells[priceIndex];
      if (categoryName.isEmpty || name.isEmpty || priceText.isEmpty) {
        continue;
      }
      final price = double.tryParse(priceText.replaceAll(',', '.'));

      final category = categoriesByName.putIfAbsent(
        categoryName,
        () => ParsedCategory(
          tempId: 'csv-category-${categoriesByName.length + 1}',
          name: categoryName,
          sortOrder: categoriesByName.length,
          sourceReference: 'CSV satır $rowNumber',
        ),
      );

      final description =
          descriptionIndex != -1 && descriptionIndex < cells.length
              ? cells[descriptionIndex]
              : null;
      final currencyCode = currencyIndex != -1 && currencyIndex < cells.length
          ? cells[currencyIndex]
          : null;

      var satisfied = 2; // name + category always present at this point
      const total = 4;
      if (price != null) satisfied++;
      if (description != null && description.isNotEmpty) satisfied++;

      products.add(ParsedProduct(
        tempId: 'csv-product-$rowNumber',
        categoryTempId: category.tempId,
        name: name,
        description: description,
        price: price,
        currencyCode: currencyCode,
        sourceReference: 'CSV satır $rowNumber',
        confidence: ImportConfidence(
          satisfiedEvidenceCount: satisfied,
          totalEvidenceCount: total,
          reasons: [
            'Ad bulundu',
            'Kategori bulundu',
            if (price != null)
              'Fiyat bulundu'
            else
              'Fiyat sayısal olarak ayrıştırılamadı',
            if (description != null && description.isNotEmpty)
              'Açıklama bulundu'
            else
              'Açıklama eksik',
          ],
        ),
      ));
    }

    return ParsedMenu(
      categories: categoriesByName.values.toList(),
      products: products,
    );
  }
}
