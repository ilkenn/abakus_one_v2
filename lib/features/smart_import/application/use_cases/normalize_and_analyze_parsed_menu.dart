import '../../../../shared/models/currency.dart';
import '../../domain/import_issue.dart';
import '../../domain/parsed_menu.dart';
import '../../domain/parsed_modifier_group.dart';
import '../../domain/parsed_product.dart';

/// Runs the "Normalize" and "Analyze" stages of the Smart Import flow in
/// one pass — Phase 7 (`docs/decisions.md` ADR-024). Pure function: adds
/// [ImportIssue]s to the [ParsedMenu] it's given, **never merges or
/// deletes a parsed record** — "do not merge records silently. Show
/// suggested merges in the review stage" — every finding here is a
/// suggestion surfaced through [ImportIssue.duplicateOfTempId], acted on
/// only by an explicit reviewer decision later.
///
/// **Honest scope**: duplicate/same-product detection compares names
/// after trimming, lowercasing, and collapsing internal whitespace —
/// true fuzzy spelling-variant detection (e.g. Levenshtein distance)
/// is not implemented; two products named "Tavuklu Bowl" and "Tavuklu
/// Bovl" (a typo) will not be flagged as the same product by this pass.
/// Embedded-modifier-group detection is a coarse keyword heuristic
/// (Turkish/English size/portion vocabulary in a description), not real
/// text understanding — every suggestion it produces carries
/// [ParsedModifierGroup.isEmbeddedSuggestion] `true` and must be
/// reviewed, never auto-applied.
class NormalizeAndAnalyzeParsedMenu {
  const NormalizeAndAnalyzeParsedMenu();

  static const _embeddedModifierKeywords = [
    'boyut',
    'seçenek',
    'size',
    'küçük',
    'orta',
    'büyük',
  ];

  ParsedMenu call(ParsedMenu menu) {
    final issues = <ImportIssue>[...menu.issues];
    var issueSequence = 0;
    String nextIssueId() => 'issue-${++issueSequence}';

    // Duplicate categories (normalized name equality).
    final categoryByNormalizedName = <String, String>{};
    for (final category in menu.categories) {
      final normalized = _normalize(category.name);
      final existingTempId = categoryByNormalizedName[normalized];
      if (existingTempId != null) {
        issues.add(ImportIssue(
          id: nextIssueId(),
          severity: ImportIssueSeverity.warning,
          code: 'duplicate_category',
          message: 'Olası tekrar eden kategori: "${category.name}"',
          relatedTempId: category.tempId,
          duplicateOfTempId: existingTempId,
        ));
      } else {
        categoryByNormalizedName[normalized] = category.tempId;
      }
    }

    // Duplicate/same-product-in-multiple-sections + conflicting prices.
    final productsByNormalizedName = <String, List<ParsedProduct>>{};
    for (final product in menu.products) {
      productsByNormalizedName
          .putIfAbsent(_normalize(product.name), () => [])
          .add(product);
    }
    for (final group in productsByNormalizedName.values) {
      if (group.length < 2) continue;
      final firstCategory = group.first.categoryTempId;
      final acrossCategories =
          group.any((p) => p.categoryTempId != firstCategory);
      for (var i = 1; i < group.length; i++) {
        issues.add(ImportIssue(
          id: nextIssueId(),
          severity: ImportIssueSeverity.warning,
          code: acrossCategories
              ? 'product_in_multiple_categories'
              : 'duplicate_product',
          message: acrossCategories
              ? '"${group[i].name}" birden fazla bölümde görünüyor'
              : 'Olası tekrar eden ürün: "${group[i].name}"',
          relatedTempId: group[i].tempId,
          duplicateOfTempId: group.first.tempId,
        ));
      }
      final prices = group.map((p) => p.price).whereType<double>().toSet();
      if (prices.length > 1) {
        for (final product in group) {
          issues.add(ImportIssue(
            id: nextIssueId(),
            severity: ImportIssueSeverity.warning,
            code: 'conflicting_price',
            message: '"${product.name}" için çelişen fiyatlar bulundu: $prices',
            relatedTempId: product.tempId,
          ));
        }
      }
    }

    // Per-product field-level issues.
    for (final product in menu.products) {
      if (product.price == null) {
        issues.add(ImportIssue(
          id: nextIssueId(),
          severity: ImportIssueSeverity.error,
          code: 'invalid_price_format',
          message: '"${product.name}" için geçerli bir fiyat bulunamadı',
          relatedTempId: product.tempId,
        ));
      }
      if (product.description == null || product.description!.isEmpty) {
        issues.add(ImportIssue(
          id: nextIssueId(),
          severity: ImportIssueSeverity.info,
          code: 'missing_description',
          message: '"${product.name}" için açıklama eksik',
          relatedTempId: product.tempId,
        ));
      }
      if (product.currencyCode != null &&
          !Currency.all
              .map((c) => c.isoCode)
              .contains(product.currencyCode!.toUpperCase())) {
        issues.add(ImportIssue(
          id: nextIssueId(),
          severity: ImportIssueSeverity.error,
          code: 'invalid_currency',
          message: '"${product.name}" için geçersiz para birimi: '
              '${product.currencyCode}',
          relatedTempId: product.tempId,
        ));
      }
      final description = product.description;
      if (description != null &&
          _embeddedModifierKeywords
              .any((kw) => description.toLowerCase().contains(kw))) {
        issues.add(ImportIssue(
          id: nextIssueId(),
          severity: ImportIssueSeverity.info,
          code: 'possible_embedded_modifier_group',
          message: '"${product.name}" açıklamasında olası boyut/seçenek metni '
              'tespit edildi — modifier grubu olarak incelenebilir',
          relatedTempId: product.tempId,
        ));
      }
    }

    return menu.copyWith(issues: issues);
  }

  String _normalize(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}
