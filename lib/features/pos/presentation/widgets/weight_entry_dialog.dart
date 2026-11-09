import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../menu/domain/models/menu_product.dart';
import '../../../orders/domain/order_line_quantity_label.dart';
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
/// **ADR-067 (2026-11-09)**: now returns the entered weight in whole grams
/// ("Sepete Ekle") so the caller adds a real cart line carrying
/// `weightGrams`; the server prices it from the catalog's per-kg price
/// (`submitTakeawayOrder.ts`'s `resolveWeightGrams`). Accepts "250",
/// "250 g", "1,5 kg", "1.5kg" (see `parseWeightInputToGrams`). Previously a
/// staff reference tool only (no cart line), because the backend had no
/// weight-pricing concept.
class WeightEntryDialog extends ConsumerStatefulWidget {
  const WeightEntryDialog({super.key, required this.product});

  final MenuProduct product;

  /// The entered weight in whole grams, or `null` if dismissed.
  static Future<int?> show(BuildContext context, MenuProduct product) {
    return showDialog<int>(
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

  int? get _grams => parseWeightInputToGrams(_gramsController.text);

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

  void _confirm() {
    final grams = _grams;
    if (grams == null) return;
    Navigator.of(context).pop(grams);
  }

  @override
  Widget build(BuildContext context) {
    final grams = _grams;
    final hasInput = _gramsController.text.trim().isNotEmpty;
    final estimatedMinorUnits = grams == null
        ? null
        : estimatedWeightPriceMinorUnits(
            pricePerKgMinorUnits: (widget.product.basePrice * 100).round(),
            grams: grams,
          );

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
                keyboardType: TextInputType.text,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _confirm(),
                decoration: InputDecoration(
                  isDense: true,
                  labelText: 'Gramaj',
                  hintText: 'örn. 250, 500 g, 1,5 kg',
                  errorText: hasInput && grams == null
                      ? 'Geçerli bir gramaj girin '
                          '($minWeightGrams g – ${formatWeightGrams(maxWeightGrams)}).'
                      : null,
                  border:
                      const OutlineInputBorder(borderRadius: AppRadius.kMedium),
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
              if (grams != null && estimatedMinorUnits != null)
                Text(
                  '${formatWeightGrams(grams)} · Tahmini Tutar: '
                  '${(estimatedMinorUnits / 100).toStringAsFixed(2)} TL',
                  key: const Key('weightEstimatedPrice'),
                  style: AppTypography.priceMedium,
                ),
              const SizedBox(height: AppSpacing.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    key: const Key('closeWeightEntryDialogButton'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Kapat'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  ElevatedButton(
                    key: const Key('confirmWeightEntryButton'),
                    onPressed: grams == null ? null : _confirm,
                    child: const Text('Sepete Ekle'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
