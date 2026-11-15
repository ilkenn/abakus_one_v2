import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../orders/domain/models/order.dart';

/// ADR-085 stage 6C-1 — "Eksiksiz Hazırlandı": before a package goes to a
/// courier ("Kuryeye Ver", or "Teslim Et" for a pool courier at the
/// counter), every line of the ticket is shown — especially drinks and
/// sauces — and the box must be ticked. Resolves `true` only when ticked
/// and confirmed; the server records who and when.
Future<bool> showPackingCheckDialog(
  BuildContext context, {
  required List<Order> orders,
  String confirmLabel = 'Kuryeye Ver',
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) =>
        _PackingCheckDialog(orders: orders, confirmLabel: confirmLabel),
  );
  return confirmed == true;
}

class _PackingCheckDialog extends StatefulWidget {
  const _PackingCheckDialog({required this.orders, required this.confirmLabel});

  final List<Order> orders;
  final String confirmLabel;

  @override
  State<_PackingCheckDialog> createState() => _PackingCheckDialogState();
}

class _PackingCheckDialogState extends State<_PackingCheckDialog> {
  bool _checked = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('packingCheckDialog'),
      title: const Text('Paket Kontrolü'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Adisyondaki her kalemi (içecek, sos, yan ürünler) pakette '
              'kontrol edin.',
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.sm),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final order in widget.orders) ...[
                    Text(order.orderNumber.value,
                        style: AppTypography.titleMedium),
                    if (order.lines.isEmpty)
                      Text('Kalem bilgisi yok.',
                          style: AppTypography.bodySmall
                              .copyWith(color: AppColors.textSecondary)),
                    for (final line in order.lines)
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${line.quantity} × ${line.productName}',
                                style: AppTypography.bodyMedium),
                            if (line.modifiers.isNotEmpty)
                              Text(
                                line.modifiers
                                    .map((m) => m.quantity > 1
                                        ? '${m.quantity} × ${m.optionName}'
                                        : m.optionName)
                                    .join(', '),
                                style: AppTypography.bodySmall
                                    .copyWith(color: AppColors.textSecondary),
                              ),
                            if (line.excludedIngredients.isNotEmpty)
                              Text(
                                'Çıkar: ${line.excludedIngredients.join(', ')}',
                                style: AppTypography.bodySmall
                                    .copyWith(color: AppColors.warning),
                              ),
                            if (line.kitchenNote.trim().isNotEmpty)
                              Text('Not: ${line.kitchenNote.trim()}',
                                  style: AppTypography.bodySmall),
                          ],
                        ),
                      ),
                    const Divider(),
                  ],
                ],
              ),
            ),
            CheckboxListTile(
              key: const Key('packingChecked'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _checked,
              onChanged: (value) => setState(() => _checked = value ?? false),
              title: const Text('Eksiksiz Hazırlandı'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('packingCancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Vazgeç'),
        ),
        ElevatedButton(
          key: const Key('packingConfirm'),
          onPressed: _checked ? () => Navigator.of(context).pop(true) : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
