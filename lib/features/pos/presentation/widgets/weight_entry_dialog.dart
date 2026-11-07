import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../menu/domain/models/menu_product.dart';
import '../../data/scale_reader_port.dart';
import '../providers/pos_workspace_providers.dart';

/// Adım 4 (2026-11-07) — "Tartılı Ürünler İçin Gramaj Giriş Desteği". Opened
/// instead of the normal single-tap-add for any [MenuProduct] whose
/// [MenuProduct.saleUnit] is [SaleUnit.kilogram]. Lets staff type a weight,
/// or try [ScaleReaderPort] (always [ScaleReadingOutcome.unavailable]
/// today — no real serial-port scale protocol has been specified yet), and
/// shows the resulting estimated price (reading [MenuProduct.basePrice] as
/// ₺/kg).
///
/// **Deliberately never adds a cart line** — the backend's order-line
/// `quantity` is an integer capped at 20 with no weight-based pricing
/// concept (see `docs/decisions.md`'s Adım 4 entry), so there is today no
/// correct way to turn a gram reading into a real priced line. This is the
/// same disclosed "real wiring is a separate decision" scope
/// `UnavailablePaxGmp3TerminalClient` already established for the PAX
/// terminal — a staff reference tool today, the UI this feature reuses
/// once that pricing decision is made.
class WeightEntryDialog extends ConsumerStatefulWidget {
  const WeightEntryDialog({super.key, required this.product});

  final MenuProduct product;

  static Future<void> show(BuildContext context, MenuProduct product) {
    return showDialog<void>(
      context: context,
      builder: (_) => WeightEntryDialog(product: product),
    );
  }

  @override
  ConsumerState<WeightEntryDialog> createState() => _WeightEntryDialogState();
}

class _WeightEntryDialogState extends ConsumerState<WeightEntryDialog> {
  final _gramsController = TextEditingController();
  String? _scaleMessage;
  bool _reading = false;

  @override
  void dispose() {
    _gramsController.dispose();
    super.dispose();
  }

  double? get _grams =>
      double.tryParse(_gramsController.text.replaceAll(',', '.'));

  Future<void> _readFromScale() async {
    setState(() {
      _reading = true;
      _scaleMessage = null;
    });
    final reading = await ref.read(scaleReaderPortProvider).readWeightGrams();
    if (!mounted) return;
    setState(() {
      _reading = false;
      if (reading.outcome == ScaleReadingOutcome.read &&
          reading.grams != null) {
        _gramsController.text = reading.grams!.toString();
      } else {
        _scaleMessage = reading.message ?? 'Terazi okunamadı.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final grams = _grams;
    final estimatedPrice =
        grams != null ? widget.product.basePrice * (grams / 1000) : null;

    return Dialog(
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.kLarge),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Gramaj / Miktar Girin',
                  style: AppTypography.titleMedium),
              const SizedBox(height: AppSpacing.xs),
              Text(widget.product.name, style: AppTypography.bodyMedium),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '${widget.product.basePrice.toStringAsFixed(2)} TL / kg',
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                key: const Key('weightGramsField'),
                controller: _gramsController,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Gramaj',
                  suffixText: 'g',
                  border: OutlineInputBorder(borderRadius: AppRadius.kMedium),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                key: const Key('readFromScaleButton'),
                onPressed: _reading ? null : _readFromScale,
                icon: _reading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.scale_outlined, size: 18),
                label: const Text('Teraziden Oku'),
              ),
              if (_scaleMessage != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _scaleMessage!,
                  style:
                      AppTypography.bodySmall.copyWith(color: AppColors.error),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              if (estimatedPrice != null)
                Text(
                  'Tahmini Tutar: ${estimatedPrice.toStringAsFixed(2)} TL',
                  style: AppTypography.priceMedium,
                ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Bu gramaj henüz adisyona otomatik eklenmiyor — fiyatlandırma '
                've sipariş satırı entegrasyonu ayrı bir adımda '
                'tamamlanacak. Bu tutarı şimdilik sözlü/elle bildirin.',
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: const Key('closeWeightEntryDialogButton'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Kapat'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
