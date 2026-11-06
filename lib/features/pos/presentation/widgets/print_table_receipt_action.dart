import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../admin/presentation/providers/admin_dependencies_provider.dart';
import '../../../menu/presentation/providers/menu_catalog_provider.dart';
import '../../../printing/data/windows_raw_printer_adapter.dart';
import '../../data/pos_action_gateway.dart' show PosDeviceContext;
import '../../data/pos_operational_view_gateway.dart';
import '../providers/pos_workspace_providers.dart';

/// Shared "Yazdır" action behind all three trigger points the 2026-11-05
/// printer integration wires up: the Masalar grid's quick button
/// (`pos_branch_overview_screen.dart`), the table workspace's quick-action
/// bar, and its "... Diğer" grid tile (both `pos_table_workspace_screen
/// .dart`) — one place for the loading/success/error feedback so all three
/// behave identically rather than drifting.
Future<void> printTableReceipt({
  required BuildContext context,
  required WidgetRef ref,
  required PosDeviceContext ctx,
  required String tableId,
  // `null` (only the Masalar grid's quick button does this — the
  // workspace's own trigger points already know their checkId or disable
  // the button) asks [PrintTableReceipt] to resolve the table's currently
  // open/ready-for-payment check itself.
  required String? checkId,
  required String tableName,
}) async {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Fiş yazdırılıyor...')),
  );

  try {
    final products = ref.read(menuProductsProvider);
    final productById = {for (final p in products) p.id: p};
    final branch =
        await ref.read(branchRepositoryProvider).findById(ctx.branchId);
    final branchName = branch?.name ?? ctx.branchId;
    final printerSettings =
        await ref.read(receiptPrinterSettingsProvider.future);

    await ref.read(printTableReceiptProvider).call(
          ctx: ctx,
          tableId: tableId,
          checkId: checkId,
          tableName: tableName,
          branchName: branchName,
          printerName: printerSettings.printerName,
          recipeFor: (productId) => productById[productId]?.description ?? '',
          codepage: printerSettings.codepage,
        );

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Fiş yazdırıldı.')),
    );
  } catch (error) {
    if (!context.mounted) return;
    final message = switch (error) {
      RawPrinterException(:final message) => message,
      PosOperationalViewException(:final message) => message,
      _ => 'Fiş yazdırılamadı.',
    };
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}
