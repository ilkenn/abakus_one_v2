import 'kitchen_routing_rule.dart';
import 'kitchen_station.dart';

/// Resolves which [KitchenStation] a kitchen line routes to — a pure
/// function over already-loaded rules, mirroring
/// `ExpeditorProjectionBuilder`/`CourierReceiptSummaryBuilder`'s shape (no
/// repository access of its own, trivially testable, no hidden I/O).
///
/// Rules are evaluated in ascending `priority` order; the first match
/// wins. No rule configured, or none matching, resolves to
/// [KitchenStation.shared] — the default Abaküs single-shared-station
/// behavior.
abstract final class KitchenRoutingResolver {
  KitchenRoutingResolver._();

  static KitchenStation resolve({
    required List<KitchenRoutingRule> rules,
    String? productId,
    String? categoryId,
    Set<String> modifierCodes = const {},
    String? channelName,
  }) {
    final ordered = [...rules]
      ..sort((a, b) => a.priority.compareTo(b.priority));
    for (final rule in ordered) {
      if (rule.criteria.matches(
        productId: productId,
        categoryId: categoryId,
        modifierCodes: modifierCodes,
        channelName: channelName,
      )) {
        return rule.targetStation;
      }
    }
    return KitchenStation.shared;
  }
}
