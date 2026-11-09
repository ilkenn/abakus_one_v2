import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../menu/domain/models/menu_product.dart';
import '../../../menu/domain/models/sale_unit.dart';
import '../../../qr/presentation/providers/menu_showcase_mode_provider.dart';

/// 2026-11-09 — the one check every "add to cart" entry point runs first.
/// In the read-only showcase menu (floor-stand QR, no table yet) nothing is
/// added; the guest is told to scan their table's QR instead. Returns
/// `true` when adding may proceed.
///
/// Kept synchronous on purpose: every call site adds to the cart
/// synchronously, so the dialog is shown fire-and-forget and the caller
/// simply returns.
///
/// 2026-11-09 (ADR-067 follow-up) — also refuses a [product] sold by
/// weight: the customer app has no weight entry and the server rejects a
/// kg line without `weightGrams`, so the guest is told to ask staff
/// instead of failing at submit. Only customer-app entry points call this;
/// the POS adds kg products through its own `WeightEntryDialog`.
bool allowCartAdd(BuildContext context, WidgetRef ref, {MenuProduct? product}) {
  if (ref.read(isMenuShowcaseActiveProvider)) {
    showDialog<void>(
      context: context,
      builder: (_) => const ShowcaseOrderingBlockedDialog(),
    );
    return false;
  }
  if (product?.saleUnit == SaleUnit.kilogram) {
    showDialog<void>(
      context: context,
      builder: (_) => const WeightProductOrderingBlockedDialog(),
    );
    return false;
  }
  return true;
}

/// "Bu ürün gramajla satılır; lütfen garsonunuzdan isteyin."
class WeightProductOrderingBlockedDialog extends StatelessWidget {
  const WeightProductOrderingBlockedDialog({super.key});

  static const message =
      'Bu ürün gramajla satılır; lütfen garsonunuzdan isteyin.';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.scale_outlined),
      title: const Text('Garsonla Sipariş'),
      content: const Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Tamam'),
        ),
      ],
    );
  }
}

/// "Sipariş verebilmek için lütfen oturduğunuz masadaki QR kodu okutun."
class ShowcaseOrderingBlockedDialog extends StatelessWidget {
  const ShowcaseOrderingBlockedDialog({super.key});

  static const message =
      'Sipariş verebilmek için lütfen oturduğunuz masadaki QR kodu okutun.';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.qr_code_2_rounded),
      title: const Text('Masadan Sipariş'),
      content: const Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Tamam'),
        ),
      ],
    );
  }
}
