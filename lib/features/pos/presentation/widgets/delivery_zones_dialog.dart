import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../data/delivery_operations_gateway.dart';
import '../../domain/delivery/delivery_zone.dart';
import '../providers/courier_dispatch_dependencies_provider.dart';
import 'delivery_order_dialogs.dart' show formatTlMinor;

/// 2026-11-12 (Faz 4, ADR-081) — "Teslimat Bölgeleri" (Kurye Ayarları):
/// the branch's neighborhood rules — "Minimum Sepet Tutarı (TL)" and
/// "Tahmini Teslimat Süresi (dk)". Everyone who opens Paket Servis orders
/// sees the list; saving is manager-and-above (the server refuses others,
/// and a neighborhood another branch already serves).
class DeliveryZonesDialog extends ConsumerStatefulWidget {
  const DeliveryZonesDialog({
    super.key,
    required this.organizationId,
    required this.branchId,
  });

  final String organizationId;
  final String branchId;

  @override
  ConsumerState<DeliveryZonesDialog> createState() =>
      _DeliveryZonesDialogState();
}

class _DeliveryZonesDialogState extends ConsumerState<DeliveryZonesDialog> {
  final _neighborhood = TextEditingController();
  final _district = TextEditingController();
  final _minimum = TextEditingController();
  final _eta = TextEditingController();
  bool _enabled = true;
  bool _saving = false;
  String? _error;

  DispatchScope get _scope =>
      (organizationId: widget.organizationId, branchId: widget.branchId);

  @override
  void dispose() {
    for (final c in [_neighborhood, _district, _minimum, _eta]) {
      c.dispose();
    }
    super.dispose();
  }

  void _edit(DeliveryZone zone) {
    setState(() {
      _neighborhood.text = zone.neighborhoodName;
      _district.text = zone.districtId;
      _minimum.text = (zone.minimumOrderMinorUnits ~/ 100).toString();
      _eta.text = zone.estimatedDeliveryMinutes?.toString() ?? '';
      _enabled = zone.enabled;
      _error = null;
    });
  }

  void _clear() {
    setState(() {
      for (final c in [_neighborhood, _district, _minimum, _eta]) {
        c.clear();
      }
      _enabled = true;
      _error = null;
    });
  }

  Future<void> _save() async {
    final neighborhood = _neighborhood.text.trim();
    final minimumTl =
        int.tryParse(_minimum.text.trim().isEmpty ? '0' : _minimum.text.trim());
    final etaText = _eta.text.trim();
    final eta = etaText.isEmpty ? null : int.tryParse(etaText);
    if (neighborhood.isEmpty) {
      setState(() => _error = 'Mahalle adını girin.');
      return;
    }
    if (minimumTl == null || minimumTl < 0 || minimumTl > 10000) {
      setState(() => _error = 'Minimum sepet 0 ile 10.000 TL arasında olmalı.');
      return;
    }
    if (etaText.isNotEmpty && (eta == null || eta < 5 || eta > 240)) {
      setState(() => _error = 'Tahmini süre 5 ile 240 dakika arasında olmalı.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(deliveryOperationsGatewayProvider).upsertZone(
            organizationId: widget.organizationId,
            branchId: widget.branchId,
            neighborhoodName: neighborhood,
            districtName: _district.text.trim(),
            minimumOrderMinorUnits: minimumTl * 100,
            estimatedDeliveryMinutes: eta,
            enabled: _enabled,
          );
      ref.invalidate(branchDeliveryZonesProvider(_scope));
      if (!mounted) return;
      _clear();
    } on DeliveryOperationsException catch (error) {
      if (!mounted) return;
      setState(() => _error = switch (error.detailCode) {
            'deliveryZone/covered-by-other-branch' =>
              'Bu mahalleye başka bir şube hizmet veriyor.',
            'deliveryZone/district-required' =>
              'İlçe girin veya Havuz Bölge Ayarları\'ndan varsayılan ilçeyi '
                  'belirleyin.',
            _ => error.isPermissionDenied
                ? 'Teslimat bölgelerini yalnızca müdür ve üstü değiştirebilir.'
                : 'Kaydedilemedi. Lütfen tekrar deneyin.',
          });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final zonesAsync = ref.watch(branchDeliveryZonesProvider(_scope));
    return AlertDialog(
      title: const Text('Teslimat Bölgeleri'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Mahalle bazında minimum sepet tutarı ve tahmini teslimat '
                'süresi. Minimumun altındaki Paket Servis siparişi yalnızca '
                'müdür onayıyla açılır; tahmini süre kurye fişine yazılır.',
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.sm),
              zonesAsync.when(
                loading: () => const SizedBox(
                    height: 80,
                    child: Center(child: CircularProgressIndicator())),
                error: (_, __) => const Text('Teslimat bölgeleri yüklenemedi.',
                    key: Key('zonesLoadError')),
                data: (data) => data.zones.isEmpty
                    ? const Text('Henüz tanımlı bölge yok.',
                        key: Key('zonesEmpty'))
                    : Column(
                        children: [
                          for (final zone in data.zones)
                            ListTile(
                              key: Key('deliveryZone-${zone.id}'),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                zone.enabled
                                    ? Icons.location_on_outlined
                                    : Icons.location_off_outlined,
                                color: zone.enabled
                                    ? AppColors.primary
                                    : AppColors.textDisabled,
                              ),
                              title: Text(
                                  '${zone.neighborhoodName} · ${zone.districtId}'),
                              subtitle: Text([
                                'Min. ${formatTlMinor(zone.minimumOrderMinorUnits)}',
                                zone.estimatedDeliveryMinutes == null
                                    ? 'Süre tanımsız'
                                    : '~${zone.estimatedDeliveryMinutes} dk',
                                if (!zone.enabled) 'Kapalı',
                              ].join(' · ')),
                              trailing: IconButton(
                                key: Key('editZone-${zone.id}'),
                                tooltip: 'Düzenle',
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () => _edit(zone),
                              ),
                            ),
                        ],
                      ),
              ),
              const Divider(height: AppSpacing.lg),
              const Text('Bölge Ekle / Düzenle',
                  style: AppTypography.labelLarge),
              const SizedBox(height: AppSpacing.xs),
              TextField(
                key: const Key('zoneNeighborhoodField'),
                controller: _neighborhood,
                decoration: const InputDecoration(labelText: 'Mahalle'),
              ),
              TextField(
                key: const Key('zoneDistrictField'),
                controller: _district,
                decoration: const InputDecoration(
                  labelText: 'İlçe',
                  helperText: 'Boş bırakılırsa şubenin varsayılan ilçesi.',
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('zoneMinimumField'),
                      controller: _minimum,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                          labelText: 'Minimum Sepet Tutarı (TL)'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TextField(
                      key: const Key('zoneEtaField'),
                      controller: _eta,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                          labelText: 'Tahmini Teslimat Süresi (dk)'),
                    ),
                  ),
                ],
              ),
              SwitchListTile(
                key: const Key('zoneEnabledSwitch'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Bölge açık'),
                value: _enabled,
                onChanged: (value) => setState(() => _enabled = value),
              ),
              if (_error != null)
                Text(_error!,
                    key: const Key('zoneError'),
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.error)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Kapat'),
        ),
        FilledButton(
          key: const Key('saveZoneButton'),
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Kaydediliyor...' : 'Bölgeyi Kaydet'),
        ),
      ],
    );
  }
}
