import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../admin/presentation/providers/admin_dependencies_provider.dart';
import '../../../orders/domain/models/order_id.dart';
import '../../../orders/presentation/providers/orders_provider.dart';
import '../../../printing/data/windows_raw_printer_adapter.dart';
import '../../../printing/domain/esc_pos_courier_slip_encoder.dart';
import '../../domain/delivery/courier_slip.dart';
import '../providers/pos_workspace_providers.dart';

/// 2026-11-11 (Faz 2) — prints the courier slip ("Kurye Fişi") for a
/// delivery order: automatically right after a staff Paket Servis order is
/// confirmed, and again on demand ([isCopy]) from the order screen and the
/// dispatch board. The slip is built from the server-written order
/// ([CourierSlip.fromOrder]) on the till's configured ESC/POS printer. Never
/// throws — the outcome is reported in a SnackBar, and a printer problem
/// never undoes the (already confirmed) order.
Future<bool> printCourierSlip({
  required BuildContext context,
  required WidgetRef ref,
  required String branchId,
  required String orderId,
  bool isCopy = false,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(
    const SnackBar(content: Text('Kurye fişi yazdırılıyor...')),
  );
  try {
    final order = await ref
        .read(canonicalOrderRepositoryProvider)
        .findById(OrderId(orderId));
    if (order == null) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Sipariş bulunamadı; fiş basılamadı.')));
      return false;
    }
    final branch = await ref.read(branchRepositoryProvider).findById(branchId);
    final printerSettings =
        await ref.read(receiptPrinterSettingsProvider.future);
    final slip = CourierSlip.fromOrder(
      order: order,
      restaurantName: 'Abaküs',
      branchName: branch?.name ?? branchId,
      isCopy: isCopy,
    );
    await ref.read(rawPrinterAdapterProvider).printRaw(
          printerName: printerSettings.printerName,
          bytes: EscPosCourierSlipEncoder.encode(slip,
              codepage: printerSettings.codepage),
          jobName: 'Kurye Fişi - ${slip.orderNumber}',
        );
    messenger
        .showSnackBar(const SnackBar(content: Text('Kurye fişi yazdırıldı.')));
    return true;
  } catch (error) {
    messenger.showSnackBar(SnackBar(
      content: Text(error is RawPrinterException
          ? error.message
          : 'Kurye fişi yazdırılamadı.'),
    ));
    return false;
  }
}
