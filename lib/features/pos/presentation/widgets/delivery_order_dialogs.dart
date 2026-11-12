import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../data/pos_phone_order_gateway.dart';
import '../providers/pos_workspace_providers.dart';

/// "250,00 TL"
String formatTlMinor(int minorUnits) {
  final whole = minorUnits ~/ 100;
  final kurus = (minorUnits % 100).abs().toString().padLeft(2, '0');
  final digits = whole.abs().toString();
  final grouped = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) grouped.write('.');
    grouped.write(digits[i]);
  }
  return '${minorUnits < 0 ? '-' : ''}$grouped,$kurus TL';
}

/// 2026-11-12 (Faz 4, ADR-081) — the server refused a Paket Servis order
/// below the neighborhood's minimum basket. A manager-tier user may approve
/// and continue ([canOverride]); anyone else is told a manager is needed.
/// Returns `true` only when the user approved.
Future<bool> confirmBelowMinimumOrder({
  required BuildContext context,
  required String neighborhoodName,
  required int minimumOrderMinorUnits,
  required int basketMinorUnits,
  required bool canOverride,
}) async {
  final shortfall = minimumOrderMinorUnits - basketMinorUnits;
  final approved = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const Key('belowMinimumDialog'),
      icon: const Icon(Icons.warning_amber_rounded, color: AppColors.warning),
      title: const Text('Minimum Sepet Tutarı Altında'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${neighborhoodName.isEmpty ? 'Bu mahalle' : neighborhoodName} '
            'için minimum sepet ${formatTlMinor(minimumOrderMinorUnits)}. '
            'Sepet ${formatTlMinor(basketMinorUnits)} '
            '(${formatTlMinor(shortfall > 0 ? shortfall : 0)} eksik).',
            style: AppTypography.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            canOverride
                ? 'Yetkili onayıyla sipariş yine de açılabilir; onay kayıt '
                    'altına alınır.'
                : 'Minimumun altındaki bir sipariş için Müdür onayı gerekir. '
                    'Sepete ürün ekleyin veya yetkili bir kullanıcı '
                    'siparişi açsın.',
            style: AppTypography.bodySmall
                .copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
      actions: canOverride
          ? [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Vazgeç'),
              ),
              ElevatedButton(
                key: const Key('approveBelowMinimumButton'),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Onayla ve Devam Et'),
              ),
            ]
          : [
              ElevatedButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Tamam'),
              ),
            ],
    ),
  );
  return approved ?? false;
}

/// 2026-11-12 (Faz 4, ADR-082) — KVKK "Kaydı Sil" for a local customer-book
/// record, from the POS customer search (manager and above; the server
/// re-checks). The user types "SİL" to confirm and may note the request
/// reference (e.g. the petition number). Pops with the
/// [PosCustomerErasureResult] on success, `null` otherwise.
class PosCustomerErasureDialog extends ConsumerStatefulWidget {
  const PosCustomerErasureDialog({
    super.key,
    required this.organizationId,
    required this.customer,
  });

  final String organizationId;
  final PosCustomerBookEntry customer;

  @override
  ConsumerState<PosCustomerErasureDialog> createState() =>
      _PosCustomerErasureDialogState();
}

class _PosCustomerErasureDialogState
    extends ConsumerState<PosCustomerErasureDialog> {
  static const confirmationWord = 'SİL';

  final _confirmController = TextEditingController();
  final _referenceController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _confirmController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  bool get _confirmed =>
      _confirmController.text.trim().toUpperCase() == confirmationWord ||
      _confirmController.text.trim() == 'SIL';

  Future<void> _erase() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref.read(posPhoneOrderGatewayProvider).eraseCustomer(
            organizationId: widget.organizationId,
            posCustomerId: widget.customer.id,
            requestReference: _referenceController.text,
          );
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } on PosPhoneOrderException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = switch (e.detailCode) {
          'posCustomer/active-orders' =>
            'Müşterinin devam eden ${e.activeOrderCount ?? ''} siparişi var. '
                'Sipariş tamamlanınca veya iptal edilince tekrar deneyin.',
          'posCustomer/not-found' => 'Bu kayıt zaten silinmiş.',
          _ => e.code.startsWith('permission')
              ? 'KVKK silme işlemi için Müdür yetkisi gerekir.'
              : 'Kayıt silinemedi. Lütfen tekrar deneyin.',
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final customer = widget.customer;
    return AlertDialog(
      key: const Key('posCustomerErasureDialog'),
      icon: const Icon(Icons.privacy_tip_outlined, color: AppColors.error),
      title: const Text('KVKK — Müşteri Kaydını Sil'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${customer.displayName} · '
              '${customer.phoneNumber ?? customer.phoneMasked}',
              style: AppTypography.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Müşteri defterindeki kayıt kalıcı olarak silinir. Geçmiş '
              'siparişlerdeki ad, telefon, açık adres ve kurye notu '
              'anonimleştirilir; tutarlar ve mahalle bilgisi raporlar için '
              'korunur. Bu işlem geri alınamaz.',
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const Key('erasureReferenceField'),
              controller: _referenceController,
              maxLength: 64,
              decoration: const InputDecoration(
                labelText: 'Talep Referansı (isteğe bağlı)',
                hintText: 'ör. Dilekçe no',
                isDense: true,
                border: OutlineInputBorder(borderRadius: AppRadius.kSmall),
              ),
            ),
            TextField(
              key: const Key('erasureConfirmField'),
              controller: _confirmController,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Onaylamak için SİL yazın',
                isDense: true,
                border: OutlineInputBorder(borderRadius: AppRadius.kSmall),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(_error!,
                    key: const Key('erasureError'),
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.error)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        ElevatedButton(
          key: const Key('confirmErasureButton'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.error,
            foregroundColor: AppColors.onPrimary,
          ),
          onPressed: _busy || !_confirmed ? null : _erase,
          child: _busy
              ? const SizedBox.square(
                  dimension: AppSpacing.md,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Kalıcı Olarak Sil'),
        ),
      ],
    );
  }
}
