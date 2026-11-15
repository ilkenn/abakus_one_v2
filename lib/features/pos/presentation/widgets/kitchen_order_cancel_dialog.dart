import 'package:flutter/material.dart';

import '../../../orders/domain/models/order_channel.dart';
import '../../data/kitchen_action_gateway.dart';
import '../../domain/staff_reason_rule.dart';

/// What staff chose in [showKitchenOrderCancelDialog].
typedef KitchenOrderCancellation = ({
  DineInCancellationReasonCode reasonCode,
  String reasonMessage,
});

/// 2026-11-08 — the whole-order "Siparişi İptal Et" reason picker, shared by
/// the KDS board card's footer, the KDS detail screen and the courier
/// settlement. ADR-085 stage 6C-2: a written explanation of at least
/// [minStaffReasonLength] characters is required too. Returns `null` when
/// the user backs out.
Future<KitchenOrderCancellation?> showKitchenOrderCancelDialog(
  BuildContext context, {
  required OrderChannel channel,
}) =>
    showDialog<KitchenOrderCancellation>(
      context: context,
      builder: (_) => _KitchenOrderCancelDialog(channel: channel),
    );

class _KitchenOrderCancelDialog extends StatefulWidget {
  const _KitchenOrderCancelDialog({required this.channel});

  final OrderChannel channel;

  @override
  State<_KitchenOrderCancelDialog> createState() =>
      _KitchenOrderCancelDialogState();
}

class _KitchenOrderCancelDialogState extends State<_KitchenOrderCancelDialog> {
  final _formKey = GlobalKey<FormState>();
  final _message = TextEditingController();
  var _selected = DineInCancellationReasonCode.itemUnavailable;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  void _confirm() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context)
        .pop((reasonCode: _selected, reasonMessage: _message.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Siparişi İptal Et'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioGroup<DineInCancellationReasonCode>(
                groupValue: _selected,
                onChanged: (value) =>
                    setState(() => _selected = value ?? _selected),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final code in DineInCancellationReasonCode.values)
                      RadioListTile<DineInCancellationReasonCode>(
                        value: code,
                        title: Text(kitchenOrderCancellationReasonLabel(
                          code,
                          channel: widget.channel,
                        )),
                      ),
                  ],
                ),
              ),
              TextFormField(
                key: const Key('orderCancelReasonMessage'),
                controller: _message,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Açıklama (zorunlu)',
                ),
                validator: staffReasonError,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        ElevatedButton(
          key: const Key('orderCancelConfirm'),
          onPressed: _confirm,
          child: const Text('Siparişi İptal Et'),
        ),
      ],
    );
  }
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
