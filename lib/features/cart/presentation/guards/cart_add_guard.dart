import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../qr/presentation/providers/menu_showcase_mode_provider.dart';

/// 2026-11-09 — the one check every "add to cart" entry point runs first.
/// In the read-only showcase menu (floor-stand QR, no table yet) nothing is
/// added; the guest is told to scan their table's QR instead. Returns
/// `true` when adding may proceed.
///
/// Kept synchronous on purpose: every call site adds to the cart
/// synchronously, so the dialog is shown fire-and-forget and the caller
/// simply returns.
bool allowCartAdd(BuildContext context, WidgetRef ref) {
  if (!ref.read(isMenuShowcaseActiveProvider)) return true;
  showDialog<void>(
    context: context,
    builder: (_) => const ShowcaseOrderingBlockedDialog(),
  );
  return false;
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
