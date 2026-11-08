import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/live_table_bill_gateway.dart';
import 'active_table_context_provider.dart';

final liveTableBillGatewayProvider = Provider<LiveTableBillGateway>(
  (ref) => const FirebaseLiveTableBillGateway(),
);

/// Adım 5 (2026-11-07) — `null` whenever there is no active table context
/// (nothing to show); otherwise the table's current running bill.
/// `autoDispose` + a widget-level poll (`_LiveTableBillBanner`) is this
/// screen's own refresh mechanism — mirrors `PosBranchOverviewScreen`'s
/// existing bounded-interval poll rather than introducing a new Firestore
/// listener for this.
final liveTableBillProvider =
    FutureProvider.autoDispose<LiveTableBill?>((ref) async {
  final context = ref.watch(activeTableContextProvider);
  if (context == null) return null;
  return ref
      .watch(liveTableBillGatewayProvider)
      .getLiveTableBill(tableSessionId: context.session.id);
});
