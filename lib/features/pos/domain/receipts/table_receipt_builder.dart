import '../../../printing/domain/receipt_document.dart';
import '../../data/pos_operational_view_gateway.dart';

/// Builds a [ReceiptDocument] for a table's "ara hesap fişi" (interim till
/// receipt) from the same [PosTableOperationalView] the workspace/checkout
/// screens already load — no separate backend read, mirroring
/// `KitchenTicketMapper.fromOrder`'s "snapshot of data already in hand"
/// shape, just for the printed receipt instead of the kitchen ticket.
abstract final class TableReceiptBuilder {
  TableReceiptBuilder._();

  /// [checkId] selects which of [view.checks] this receipt totals against
  /// — a table can have more than one check (split accounts), and the
  /// receipt must total the one the staff member actually opened, never
  /// "whichever check happens to be first."
  ///
  /// [recipeFor] looks up a product's standard recipe text
  /// (`MenuProduct.description`) by `productId` — `null`/empty is treated
  /// as "no recipe text available" rather than an error, since not every
  /// product necessarily has one recorded.
  ///
  /// Only `accepted` lines are billed — matches every other check/payment
  /// computation in this codebase (`_ensureAllocationsThenFinalize` et
  /// al.), never a line still `pendingApproval`/`proposedChange`/rejected.
  static ReceiptDocument build({
    required PosTableOperationalView view,
    required String checkId,
    required String restaurantName,
    required String branchName,
    required String tableName,
    required String receiptNumber,
    required DateTime issuedAt,
    required String Function(String productId) recipeFor,
  }) {
    final check = view.checks.firstWhere(
      (c) => c['id'] == checkId,
      orElse: () => const <String, dynamic>{},
    );
    final currencyCode = check['currencyCode'] as String? ?? 'TRY';
    final computedTotalMinorUnits =
        (check['computedTotalMinorUnits'] as num?)?.toInt() ?? 0;

    final lines = <ReceiptLineItem>[];
    for (final order in view.orders) {
      for (final line in order.lines) {
        if (line.status != 'accepted') continue;
        final recipe = line.productId == null ? '' : recipeFor(line.productId!);
        final selectionNotes = _selectionNotesFor(line);
        lines.add(ReceiptLineItem(
          quantity: line.quantity,
          productName: line.productName,
          unitPriceMinorUnits: line.unitPriceMinorUnits,
          totalPriceMinorUnits: line.unitPriceMinorUnits * line.quantity,
          recipeSummary: recipe.isEmpty ? null : recipe,
          selectionNotes: selectionNotes,
        ));
      }
    }

    final subtotalMinorUnits =
        lines.fold<int>(0, (sum, l) => sum + l.totalPriceMinorUnits);
    final discountMinorUnits = (subtotalMinorUnits - computedTotalMinorUnits)
        .clamp(0, subtotalMinorUnits);

    return ReceiptDocument(
      restaurantName: restaurantName,
      branchName: branchName,
      tableName: tableName,
      issuedAt: issuedAt,
      receiptNumber: receiptNumber,
      lines: lines,
      subtotalMinorUnits: subtotalMinorUnits,
      discountMinorUnits: discountMinorUnits,
      totalMinorUnits: computedTotalMinorUnits,
      currencyCode: currencyCode,
    );
  }

  /// Mirrors `KitchenTicketMapper._ingredientSummaryFor` — grouped modifier
  /// selections (by `groupName`), then a trailing "ÇIKAR: ..." line for
  /// excluded ingredients, then the free-text kitchen note if any. Kept as
  /// its own small function here rather than importing that private
  /// method (it isn't exposed), since the grouping rule itself is simple
  /// and the two call sites read genuinely different wire shapes
  /// (`OrderLine.modifiers` there vs. [PosOrderLineModifierSummary] here).
  static List<String> _selectionNotesFor(PosOrderLineSummary line) {
    final order = <String>[];
    final byGroup = <String, List<String>>{};
    for (final modifier in line.modifiers) {
      byGroup.putIfAbsent(modifier.groupName, () {
        order.add(modifier.groupName);
        return <String>[];
      }).add(_modifierDisplay(modifier));
    }
    final result = [
      for (final groupName in order)
        '$groupName: ${byGroup[groupName]!.join(", ")}',
    ];
    if (line.excludedIngredients.isNotEmpty) {
      result.add('ÇIKAR: ${line.excludedIngredients.join(", ")}');
    }
    if (line.kitchenNote.trim().isNotEmpty) {
      result.add(line.kitchenNote.trim());
    }
    return result;
  }

  static String _modifierDisplay(PosOrderLineModifierSummary modifier) {
    final qtyLabel = modifier.quantity > 1
        ? '${modifier.optionName} x${modifier.quantity}'
        : modifier.optionName;
    if (modifier.unitExtraPriceMinorUnits == 0) return qtyLabel;
    final totalExtraMinorUnits =
        modifier.unitExtraPriceMinorUnits * modifier.quantity;
    final wholeTl = totalExtraMinorUnits ~/ 100;
    return '$qtyLabel (+$wholeTl TL)';
  }
}
