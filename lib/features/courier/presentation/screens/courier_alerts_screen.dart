import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/error_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../data/courier_oversight_gateway.dart';
import '../../domain/pay/courier_pay_models.dart';
import '../providers/courier_oversight_providers.dart';
import '../widgets/courier_earnings_tab.dart';

/// ADR-085 stage 6C-1 — "Kurye Uyarıları" (cashier, packing lead, manager,
/// admin, owner): couriers over the branch's cash limit and packages late
/// on the road, red, refreshed every minute. A manager or admin sets the
/// limit and the threshold here ("Kurye Ayarları"). Alerts close by
/// themselves (settlement, delivery).
class CourierAlertsScreen extends ConsumerWidget {
  const CourierAlertsScreen({
    super.key,
    required this.organizationId,
    required this.branchId,
  });

  final String organizationId;
  final String branchId;

  Future<void> _openSettings(BuildContext context) => showDialog<void>(
        context: context,
        builder: (_) => _CourierSettingsDialog(
            organizationId: organizationId, branchId: branchId),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alertsAsync =
        ref.watch(courierOperationalAlertsProvider(organizationId));
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Kurye Uyarıları'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          IconButton(
            key: const Key('alertsRefresh'),
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref
                .invalidate(courierOperationalAlertsProvider(organizationId)),
          ),
          IconButton(
            key: const Key('courierSettingsOpen'),
            tooltip: 'Kurye Ayarları',
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => _openSettings(context),
          ),
        ],
      ),
      body: SafeArea(
        child: CourierAlertsRefresher(
          organizationId: organizationId,
          child: alertsAsync.when(
            loading: () => const LoadingView(message: 'Uyarılar yükleniyor...'),
            error: (error, _) => ErrorView(
              message: error is CourierOversightException
                  ? error.message
                  : 'Uyarılar yüklenemedi.',
              retryLabel: 'Tekrar Dene',
              onRetry: () => ref
                  .invalidate(courierOperationalAlertsProvider(organizationId)),
            ),
            data: (alerts) {
              if (alerts.isEmpty) {
                return const EmptyView(
                  key: Key('noCourierAlerts'),
                  icon: Icons.check_circle_outline,
                  message: 'Açık kurye uyarısı yok.',
                );
              }
              return ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  for (final alert in alerts) _AlertCard(alert: alert),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alert});

  final CourierOperationalAlert alert;

  @override
  Widget build(BuildContext context) {
    final cash = alert.type == CourierAlertType.cashLimit;
    final title = cash
        ? '${alert.courierName} — nakit limiti doldu'
        : '${alert.orderNumber ?? ''} — GECİKTİ (${alert.minutes ?? 0} dk)';
    final body = cash
        ? 'Üzerindeki nakit ${formatPayAmount(alert.amountMinorUnits ?? 0)}'
            '${alert.limitMinorUnits == null ? '' : ' · limit ${formatPayAmount(alert.limitMinorUnits!)}'}'
            ' — kasaya teslim etmeli.'
        : '${alert.courierName} · yola çıkalı ${alert.minutes ?? 0} dakika oldu, '
            'teslim edilmedi.';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        key: Key('alert-${alert.alertId}'),
        borderColor: AppColors.error,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(cash ? Icons.payments_outlined : Icons.timer_off_outlined,
                color: AppColors.error),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: AppTypography.bodyLarge
                          .copyWith(color: AppColors.error)),
                  Text(body, style: AppTypography.bodyMedium),
                  Text(
                    'Başladı: ${formatClock(alert.openedAt)}',
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CourierSettingsDialog extends ConsumerStatefulWidget {
  const _CourierSettingsDialog(
      {required this.organizationId, required this.branchId});

  final String organizationId;
  final String branchId;

  @override
  ConsumerState<_CourierSettingsDialog> createState() =>
      _CourierSettingsDialogState();
}

class _CourierSettingsDialogState
    extends ConsumerState<_CourierSettingsDialog> {
  final _formKey = GlobalKey<FormState>();
  final _cash = TextEditingController();
  final _late = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final settings = await ref.read(courierOversightGatewayProvider).settings(
          organizationId: widget.organizationId, branchId: widget.branchId);
      if (!mounted) return;
      _cash.text = minorUnitsToLiraText(settings.cashLimitMinorUnits);
      _late.text = '${settings.lateDeliveryMinutes}';
    } on CourierOversightException catch (error) {
      if (mounted) _error = error.message;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _cash.dispose();
    _late.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(courierOversightGatewayProvider).saveSettings(
        organizationId: widget.organizationId,
        branchId: widget.branchId,
        settings: (
          cashLimitMinorUnits: parseLiraToMinorUnits(_cash.text)!,
          lateDeliveryMinutes: int.parse(_late.text.trim()),
        ),
      );
      messenger.showSnackBar(
          const SnackBar(content: Text('Kurye ayarları kaydedildi.')));
      navigator.pop();
    } on CourierOversightException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Kurye Ayarları'),
      content: _loading
          ? const SizedBox(
              height: 80, child: Center(child: CircularProgressIndicator()))
          : Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    key: const Key('settingsCashLimit'),
                    controller: _cash,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Kurye nakit limiti', suffixText: 'TL'),
                    validator: (v) {
                      final minor = parseLiraToMinorUnits(v ?? '');
                      return minor == null || minor == 0
                          ? 'Geçerli bir tutar girin'
                          : null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    key: const Key('settingsLateMinutes'),
                    controller: _late,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Gecikme süresi (yola çıkıştan)',
                        suffixText: 'dk'),
                    validator: (v) {
                      final minutes = int.tryParse((v ?? '').trim());
                      return minutes == null || minutes < 5 || minutes > 240
                          ? '5 ile 240 dakika arasında olmalı'
                          : null;
                    },
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(_error!,
                        style: AppTypography.bodySmall
                            .copyWith(color: AppColors.error)),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Ayarları şubenin Müdürü veya Yönetici değiştirebilir.',
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        ElevatedButton(
          key: const Key('settingsSave'),
          onPressed: _loading || _saving ? null : _save,
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}
