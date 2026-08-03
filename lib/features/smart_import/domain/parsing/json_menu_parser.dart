import 'dart:convert';

import '../import_confidence.dart';
import '../import_issue.dart';
import '../parsed_category.dart';
import '../parsed_menu.dart';
import '../parsed_product.dart';

/// Deterministic JSON parser — Phase 7 (`docs/decisions.md` ADR-024).
/// Uses `dart:convert` only (no new dependency). Expected shape:
/// ```json
/// {
///   "categories": [{"name": "Bowl"}],
///   "products": [
///     {"category": "Bowl", "name": "Tavuklu Bowl", "description": "...",
///      "price": 189.90, "currency": "TRY"}
///   ]
/// }
/// ```
/// A malformed document produces a single [ImportIssue] rather than
/// throwing — parse failure is reported through the normal review flow,
/// not an exception a caller must separately catch.
class JsonMenuParser {
  const JsonMenuParser();

  ParsedMenu parse(String rawJson) {
    final Map<String, dynamic> decoded;
    try {
      final parsed = jsonDecode(rawJson);
      if (parsed is! Map<String, dynamic>) {
        return const ParsedMenu(issues: [
          ImportIssue(
            id: 'json-root-not-object',
            severity: ImportIssueSeverity.error,
            code: 'invalid_json_root',
            message: 'Kök JSON değeri bir nesne olmalı.',
          ),
        ]);
      }
      decoded = parsed;
    } on FormatException {
      return const ParsedMenu(issues: [
        ImportIssue(
          id: 'json-parse-error',
          severity: ImportIssueSeverity.error,
          code: 'invalid_json',
          message: 'Geçersiz JSON biçimi.',
        ),
      ]);
    }

    final categoriesByName = <String, ParsedCategory>{};
    final rawCategories = decoded['categories'];
    if (rawCategories is List) {
      for (final entry in rawCategories) {
        if (entry is Map && entry['name'] is String) {
          final name = entry['name'] as String;
          categoriesByName.putIfAbsent(
            name,
            () => ParsedCategory(
              tempId: 'json-category-${categoriesByName.length + 1}',
              name: name,
              sortOrder: categoriesByName.length,
              sourceReference: 'JSON categories[]',
            ),
          );
        }
      }
    }

    final products = <ParsedProduct>[];
    final rawProducts = decoded['products'];
    if (rawProducts is List) {
      var index = 0;
      for (final entry in rawProducts) {
        index++;
        if (entry is! Map) continue;
        final name = entry['name'];
        final categoryName = entry['category'];
        if (name is! String || name.isEmpty) continue;
        if (categoryName is! String || categoryName.isEmpty) continue;

        final category = categoriesByName.putIfAbsent(
          categoryName,
          () => ParsedCategory(
            tempId: 'json-category-${categoriesByName.length + 1}',
            name: categoryName,
            sortOrder: categoriesByName.length,
            sourceReference: 'JSON products[]',
          ),
        );

        final priceRaw = entry['price'];
        final price = priceRaw is num ? priceRaw.toDouble() : null;
        final description = entry['description'] is String
            ? entry['description'] as String
            : null;
        final currencyCode =
            entry['currency'] is String ? entry['currency'] as String : null;

        var satisfied = 2;
        const total = 4;
        if (price != null) satisfied++;
        if (description != null && description.isNotEmpty) satisfied++;

        products.add(ParsedProduct(
          tempId: 'json-product-$index',
          categoryTempId: category.tempId,
          name: name,
          description: description,
          price: price,
          currencyCode: currencyCode,
          sourceReference: 'JSON products[$index]',
          confidence: ImportConfidence(
            satisfiedEvidenceCount: satisfied,
            totalEvidenceCount: total,
            reasons: [
              'Ad bulundu',
              'Kategori bulundu',
              if (price != null)
                'Fiyat bulundu'
              else
                'Fiyat alanı sayısal değil veya eksik',
              if (description != null && description.isNotEmpty)
                'Açıklama bulundu'
              else
                'Açıklama eksik',
            ],
          ),
        ));
      }
    }

    return ParsedMenu(
      categories: categoriesByName.values.toList(),
      products: products,
    );
  }
}
