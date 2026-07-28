import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../orders/domain/receipt/foreign_currency_equivalent.dart';
import '../../../orders/domain/receipt/foreign_currency_equivalents_calculator.dart';
import 'pos_dependencies_provider.dart';
import 'pos_order_session_provider.dart';

/// The current session's grand total converted into every currency the
/// business accepts (EUR/USD today) — the **only** place this computation
/// happens; `PosCashierScreen` only ever renders whatever this resolves
/// to, never computes a currency value itself.
///
/// Resolves to an empty list (not an error) when no rate is available —
/// `ForeignCurrencyEquivalentsCalculator.build` already catches a failing
/// `ExchangeRateProvider` per currency — so the UI's "unavailable" state
/// is simply "the list came back empty," not a separate error path to
/// handle.
final posForeignCurrencyEquivalentsProvider =
    FutureProvider.autoDispose<List<ForeignCurrencyEquivalent>>((ref) async {
  final session = ref.watch(posOrderSessionProvider).session;
  if (session == null) return const [];
  final provider = ref.watch(exchangeRateProviderProvider);
  return ForeignCurrencyEquivalentsCalculator.build(
    accountingTotal: session.pricing.grandTotal,
    provider: provider,
  );
});
