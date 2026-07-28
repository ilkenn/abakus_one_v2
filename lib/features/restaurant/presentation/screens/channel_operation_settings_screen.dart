import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/clock_provider.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../../../shared/widgets/layout/app_section_header.dart';
import '../../../orders/domain/models/order_channel.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../application/use_cases/emergency_close_delivery_channels.dart';
import '../../application/use_cases/set_channel_acceptance_mode.dart';
import '../../application/use_cases/set_channel_operational_state.dart';
import '../../domain/models/channel_acceptance_mode.dart';
import '../../domain/models/channel_operation_policy.dart';
import '../../domain/models/channel_operational_state.dart';
import '../providers/restaurant_operations_dependencies_provider.dart';

/// Per-branch, per-channel acceptance-mode/operational-state settings, plus
/// a branch-wide delivery emergency stop.
///
/// [authorizationPolicy] is a required constructor parameter (not a
/// Riverpod-provider default) — only the emergency-stop action is gated by
/// it this sprint (routine open/busy/closed toggling by staff is not on
/// the authorization-required list), but requiring it here still follows
/// the `ClosedAccountsScreen` precedent of never reading a policy from a
/// provider with an implicit fallback.
class ChannelOperationSettingsScreen extends ConsumerStatefulWidget {
  const ChannelOperationSettingsScreen({
    super.key,
    required this.branchId,
    required this.authorizationPolicy,
    required this.staffId,
  });

  final String branchId;
  final PosAuthorizationPolicy authorizationPolicy;
  final String staffId;

  @override
  ConsumerState<ChannelOperationSettingsScreen> createState() =>
      _ChannelOperationSettingsScreenState();
}

class _ChannelOperationSettingsScreenState
    extends ConsumerState<ChannelOperationSettingsScreen> {
  Map<OrderChannel, ChannelOperationPolicy>? _policies;
  String? _emergencyMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final repository = ref.read(channelOperationPolicyRepositoryProvider);
    final policies = <OrderChannel, ChannelOperationPolicy>{};
    for (final channel in OrderChannel.values) {
      final current = await repository.findCurrent(widget.branchId, channel);
      if (current != null) policies[channel] = current;
    }
    if (!mounted) return;
    setState(() => _policies = policies);
  }

  Future<void> _setAcceptanceMode(
    OrderChannel channel,
    ChannelAcceptanceMode mode,
  ) async {
    final useCase = SetChannelAcceptanceMode(
      clock: ref.read(clockProvider),
      policyRepository: ref.read(channelOperationPolicyRepositoryProvider),
      auditRepository:
          ref.read(restaurantOperationsAuditEntryRepositoryProvider),
    );
    await useCase(
      branchId: widget.branchId,
      channel: channel,
      acceptanceMode: mode,
      updatedByStaffId: widget.staffId,
    );
    await _load();
  }

  Future<void> _setOperationalState(
    OrderChannel channel,
    ChannelOperationalState state,
  ) async {
    final useCase = SetChannelOperationalState(
      clock: ref.read(clockProvider),
      policyRepository: ref.read(channelOperationPolicyRepositoryProvider),
      auditRepository:
          ref.read(restaurantOperationsAuditEntryRepositoryProvider),
    );
    await useCase(
      branchId: widget.branchId,
      channel: channel,
      operationalState: state,
      updatedByStaffId: widget.staffId,
    );
    await _load();
  }

  Future<void> _emergencyStop() async {
    final useCase = EmergencyCloseDeliveryChannels(
      clock: ref.read(clockProvider),
      authorizationPolicy: widget.authorizationPolicy,
      policyRepository: ref.read(channelOperationPolicyRepositoryProvider),
      auditRepository:
          ref.read(restaurantOperationsAuditEntryRepositoryProvider),
    );
    try {
      await useCase(
        branchId: widget.branchId,
        reason: 'Acil durum durdurması',
        performedByStaffId: widget.staffId,
      );
      setState(() => _emergencyMessage = 'Teslimat kanalları acil durduruldu.');
      await _load();
    } catch (_) {
      setState(() => _emergencyMessage = 'Bu işlem için yetkiniz yok.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final policies = _policies;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Kanal Operasyon Ayarları'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: policies == null
            ? const LoadingView(message: 'Ayarlar yükleniyor...')
            : ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  const AppSectionHeader(title: 'Kanal Operasyon Ayarları'),
                  const SizedBox(height: AppSpacing.md),
                  for (final channel in OrderChannel.values)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: _ChannelPolicyCard(
                        channel: channel,
                        policy: policies[channel],
                        onAcceptanceModeChanged: (mode) =>
                            _setAcceptanceMode(channel, mode),
                        onOperationalStateChanged: (state) =>
                            _setOperationalState(channel, state),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.lg),
                  AppCard(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Acil Durum Durdurma',
                            style: AppTypography.bodyLarge),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Tüm teslimat kanallarını anında kapatır.',
                          style: AppTypography.bodySmall
                              .copyWith(color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.error,
                          ),
                          onPressed: _emergencyStop,
                          child: const Text('Teslimatı Acil Durdur'),
                        ),
                        if (_emergencyMessage != null) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Text(_emergencyMessage!,
                              style: AppTypography.bodySmall),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _ChannelPolicyCard extends StatelessWidget {
  const _ChannelPolicyCard({
    required this.channel,
    required this.policy,
    required this.onAcceptanceModeChanged,
    required this.onOperationalStateChanged,
  });

  final OrderChannel channel;
  final ChannelOperationPolicy? policy;
  final ValueChanged<ChannelAcceptanceMode> onAcceptanceModeChanged;
  final ValueChanged<ChannelOperationalState> onOperationalStateChanged;

  @override
  Widget build(BuildContext context) {
    final acceptanceMode =
        policy?.acceptanceMode ?? ChannelAcceptanceMode.automatic;
    final operationalState =
        policy?.operationalState ?? ChannelOperationalState.open;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(channel.name, style: AppTypography.bodyLarge),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            children: [
              for (final mode in ChannelAcceptanceMode.values)
                ChoiceChip(
                  label: Text(mode.name),
                  selected: acceptanceMode == mode,
                  onSelected: (_) => onAcceptanceModeChanged(mode),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            children: [
              for (final state in [
                ChannelOperationalState.open,
                ChannelOperationalState.busy,
                ChannelOperationalState.closed,
              ])
                ChoiceChip(
                  label: Text(state.name),
                  selected: operationalState == state,
                  onSelected: (_) => onOperationalStateChanged(state),
                ),
            ],
          ),
          if (operationalState == ChannelOperationalState.emergencyClosed)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                'Acil durumda kapalı',
                style: AppTypography.bodySmall.copyWith(color: AppColors.error),
              ),
            ),
        ],
      ),
    );
  }
}
