import 'package:flutter/material.dart';

import '../../../orders/domain/models/order_channel.dart';
import '../../data/kitchen_action_gateway.dart';

/// 2026-11-08 — the whole-order "Siparişi İptal Et" reason picker, shared by
/// the KDS board card's footer and the KDS detail screen (previously a
/// private dialog inside `KitchenOrderDetailsScreen`, dine-in only).
/// Returns the chosen reason, or `null` when the user backs out.
Future<DineInCancellationReasonCode?> showKitchenOrderCancelDialog(
  BuildContext context, {
  required OrderChannel channel,
}) async {
  var selected = DineInCancellationReasonCode.itemUnavailable;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Siparişi İptal Et'),
        content: RadioGroup<DineInCancellationReasonCode>(
          groupValue: selected,
          onChanged: (value) => setDialogState(() => selected = value!),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final code in DineInCancellationReasonCode.values)
                RadioListTile<DineInCancellationReasonCode>(
                  value: code,
                  title: Text(kitchenOrderCancellationReasonLabel(
                    code,
                    channel: channel,
                  )),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Siparişi İptal Et'),
          ),
        ],
      ),
    ),
  );
  return confirmed == true ? selected : null;
}

/// Turkish label for a cancellation reason. [DineInCancellationReasonCode
/// .guestLeft] reads as a table guest leaving for dine-in, and as a
/// customer not showing up for every other channel (where the gateway
/// sends it as `customerNoShow`).
String kitchenOrderCancellationReasonLabel(
  DineInCancellationReasonCode code, {
  required OrderChannel channel,
}) {
  switch (code) {
    case DineInCancellationReasonCode.itemUnavailable:
      return 'Ürün stokta yok';
    case DineInCancellationReasonCode.kitchenUnavailable:
      return 'Mutfak müsait değil';
    case DineInCancellationReasonCode.capacityUnavailable:
      return 'Kapasite yetersiz';
    case DineInCancellationReasonCode.guestLeft:
      return channel == OrderChannel.dineInQr
          ? 'Misafir masayı terk etti'
          : 'Müşteri gelmedi';
    case DineInCancellationReasonCode.operationalIssue:
      return 'Operasyonel sorun';
    case DineInCancellationReasonCode.other:
      return 'Diğer';
  }
}
