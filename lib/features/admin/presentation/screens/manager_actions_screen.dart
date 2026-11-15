import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/error_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../data/manager_oversight_gateway.dart';
import '../providers/manager_oversight_providers.dart';

/// ADR-085 stage 6C-2 — "Müdür İşlemleri" (Yönetici and İşletme Sahibi
/// only): every comp/discount, product or order cancellation and cash count
/// difference a branch manager applied at once, with its written reason.
/// Nothing here can be edited or deleted; "Görüldü" only marks it read.
class ManagerActionsScreen extends ConsumerStatefulWidget {
  const ManagerActionsScreen({super.key, required this.organizationId});

  final String organizationId;

  @override
  ConsumerState<ManagerActionsScreen> createState() =>
      _ManagerActionsScreenState();
}

class _ManagerActionsScreenState extends ConsumerState<ManagerActionsScreen> {
  bool _onlyUnseen = true;
  final Set<String> _busy = {};

  void _refresh() =>
      ref.invalidate(managerActionAlertsProvider(widget.organizationId));

  Future<void> _acknowledge(ManagerActionAlert alert) async {
    setState(() => _busy.add(alert.alertId));
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(managerOversightGatewayProvider).acknowledge(
          organizationId: widget.organizationId, alertId: alert.alertId);
      _refresh();
    } on ManagerOversightException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busy.remove(alert.alertId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final alertsAsync =
        ref.watch(managerActionAlertsProvider(widget.organizationId));
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Müdür İşlemleri'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          IconButton(
            key: const Key('managerActionsRefresh'),
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _refresh,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
              child: SegmentedButton<bool>(
                key: const Key('managerActionsFilter'),
                segments: const [
                  ButtonSegment(value: true, label: Text('Görülmeyenler')),
                  ButtonSegment(value: false, label: Text('Tümü')),
                ],
                selected: {_onlyUnseen},
                onSelectionChanged: (value) =>
                    setState(() => _onlyUnseen = value.first),
              ),
            ),
            Expanded(
              child: alertsAsync.when(
                loading: () =>
                    const LoadingView(message: 'Müdür işlemleri yükleniyor...'),
                error: (error, _) => ErrorView(
                  message: error is ManagerOversightException
                      ? error.message
                      : 'Müdür işlemleri yüklenemedi.',
                  retryLabel: 'Tekrar Dene',
                  onRetry: _refresh,
                ),
                data: (alerts) {
                  final shown = _onlyUnseen
                      ? alerts.where((a) => !a.acknowledged).toList()
                      : alerts;
                  if (shown.isEmpty) {
                    return EmptyView(
                      key: const Key('noManagerActions'),
                      icon: Icons.verified_user_outlined,
                      message: _onlyUnseen
                          ? 'Görülmemiş müdür işlemi yok.'
                          : 'Henüz müdür işlemi yok.',
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    itemCount: shown.length,
                    itemBuilder: (context, i) => _ManagerActionCard(
                      alert: shown[i],
                      busy: _busy.contains(shown[i].alertId),
                      onAcknowledge: () => _acknowledge(shown[i]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ManagerActionCard extends StatelessWidget {
  const _ManagerActionCard({
    required this.alert,
    required this.busy,
    required this.onAcknowledge,
  });

  final ManagerActionAlert alert;
  final bool busy;
  final VoidCallback onAcknowledge;

  IconData get _icon => switch (alert.type) {
        ManagerActionType.comp => Icons.card_giftcard_outlined,
        ManagerActionType.lineCancellation => Icons.remove_shopping_cart,
        ManagerActionType.orderCancellation => Icons.cancel_outlined,
        ManagerActionType.cashVariance => Icons.point_of_sale_outlined,
      };

  String get _subtitle {
    final parts = <String>[
      alert.actorName ?? 'Müdür',
      if (alert.orderNumber != null) alert.orderNumber!,
      if (alert.signedAmountMinorUnits != null)
        formatLira(alert.signedAmountMinorUnits!),
      if (alert.type == ManagerActionType.cashVariance)
        alert.detail == 'short' ? 'Kasa açığı' : 'Kasa fazlası',
      if (alert.type == ManagerActionType.lineCancellation &&
          (alert.detail ?? '').isNotEmpty)
        alert.detail!,
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final color =
        alert.acknowledged ? AppColors.textSecondary : AppColors.error;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        key: Key('managerAction-${alert.alertId}'),
        borderColor: alert.acknowledged ? null : AppColors.error,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_icon, color: color),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(alert.type.label,
                      style: AppTypography.bodyLarge.copyWith(color: color)),
                  Text(_subtitle, style: AppTypography.bodyMedium),
                  Text('Gerekçe: ${alert.reason}',
                      style: AppTypography.bodyMedium),
                  Text(
                    formatDateTime(alert.createdAt),
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            if (alert.acknowledged)
              Text('Görüldü',
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textSecondary))
            else
              TextButton(
                key: Key('acknowledge-${alert.alertId}'),
                onPressed: busy ? null : onAcknowledge,
                child: const Text('Görüldü'),
              ),
          ],
        ),
      ),
    );
  }
}

/// `1.234,50 TL` (Turkish grouping, kuruş only when present).
String formatLira(int minorUnits) {
  final negative = minorUnits < 0;
  final abs = minorUnits.abs();
  final whole = (abs ~/ 100).toString();
  final grouped = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) grouped.write('.');
    grouped.write(whole[i]);
  }
  final kurus = abs % 100;
  final fraction = kurus == 0 ? '' : ',${kurus.toString().padLeft(2, '0')}';
  return '${negative ? '-' : ''}$grouped$fraction TL';
}

String formatDateTime(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.day)}.${two(t.month)}.${t.year} ${two(t.hour)}:${two(t.minute)}';
}
