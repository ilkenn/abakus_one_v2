import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/clock_provider.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../application/use_cases/create_visit_reward_rule.dart';
import '../../application/use_cases/set_visit_reward_rule_active.dart';
import '../../domain/rewards/reward_type.dart';
import '../../domain/rewards/visit_reward_config.dart';
import '../../domain/rewards/visit_reward_rule.dart';
import '../providers/crm_dependencies_provider.dart';

/// Administrator "reward after X visits" configuration — Sprint 5D Part 1.
/// [requiredVisitCount] is always administrator-entered here — never a
/// hardcoded threshold.
class VisitRewardRulesAdminScreen extends ConsumerStatefulWidget {
  const VisitRewardRulesAdminScreen({
    super.key,
    this.authorizationPolicy,
    this.performedByStaffId = 'manager-1',
  });

  final PosAuthorizationPolicy? authorizationPolicy;
  final String performedByStaffId;

  @override
  ConsumerState<VisitRewardRulesAdminScreen> createState() =>
      _VisitRewardRulesAdminScreenState();
}

class _VisitRewardRulesAdminScreenState
    extends ConsumerState<VisitRewardRulesAdminScreen> {
  List<VisitRewardRule>? _rules;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final rules = await ref.read(visitRewardRuleRepositoryProvider).findAll();
    if (!mounted) return;
    setState(() => _rules = rules);
  }

  static String _rewardLabel(RewardType type) {
    switch (type) {
      case RewardType.loyaltyPoints:
        return 'Puan';
      case RewardType.coupon:
        return 'Kupon';
      case RewardType.freeProduct:
        return 'Ücretsiz Ürün';
      case RewardType.freeDrink:
        return 'Ücretsiz İçecek';
      case RewardType.dessert:
        return 'Tatlı';
      case RewardType.upgrade:
        return 'Yükseltme';
      case RewardType.campaign:
        return 'Kampanya';
    }
  }

  Future<void> _createRule() async {
    final policy = widget.authorizationPolicy;
    if (policy == null) {
      setState(() => _error = 'Yetki politikası tanımlı değil.');
      return;
    }

    final visitCountController = TextEditingController();
    final descriptionController = TextEditingController();
    var type = RewardType.freeDrink;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Yeni Ödül Kuralı'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: visitCountController,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'Gereken ziyaret sayısı'),
              ),
              DropdownButton<RewardType>(
                value: type,
                isExpanded: true,
                items: [
                  for (final t in RewardType.values)
                    DropdownMenuItem(value: t, child: Text(_rewardLabel(t))),
                ],
                onChanged: (value) =>
                    setDialogState(() => type = value ?? type),
              ),
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(labelText: 'Açıklama'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Oluştur'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    final requiredVisitCount = int.tryParse(visitCountController.text) ?? 0;

    try {
      await CreateVisitRewardRule(
        authorizationPolicy: policy,
        idGenerator: ref.read(visitRewardRuleIdGeneratorProvider),
        repository: ref.read(visitRewardRuleRepositoryProvider),
        auditRepository: ref.read(crmAuditEntryRepositoryProvider),
      )(
        requiredVisitCount: requiredVisitCount,
        rewardType: type,
        rewardConfig:
            VisitRewardConfig(description: descriptionController.text),
        performedByStaffId: widget.performedByStaffId,
        createdAt: ref.read(clockProvider).now(),
      );
      setState(() => _error = null);
      await _load();
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _toggleActive(VisitRewardRule rule) async {
    final policy = widget.authorizationPolicy;
    if (policy == null) {
      setState(() => _error = 'Yetki politikası tanımlı değil.');
      return;
    }
    try {
      await SetVisitRewardRuleActive(
        authorizationPolicy: policy,
        repository: ref.read(visitRewardRuleRepositoryProvider),
        auditRepository: ref.read(crmAuditEntryRepositoryProvider),
      )(
        ruleId: rule.id,
        isActive: !rule.isActive,
        performedByStaffId: widget.performedByStaffId,
        performedAt: ref.read(clockProvider).now(),
      );
      await _load();
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final rules = _rules;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Ziyaret Ödül Kuralları'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Yeni Kural',
            onPressed: _createRule,
          ),
        ],
      ),
      body: SafeArea(
        child: rules == null
            ? const LoadingView(message: 'Kurallar yükleniyor...')
            : Column(
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      child: Text(_error!,
                          style: AppTypography.bodySmall
                              .copyWith(color: AppColors.error)),
                    ),
                  Expanded(
                    child: rules.isEmpty
                        ? const EmptyView(
                            icon: Icons.card_giftcard_outlined,
                            message: 'Henüz ödül kuralı tanımlanmadı.',
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            itemCount: rules.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: AppSpacing.sm),
                            itemBuilder: (context, index) {
                              final rule = rules[index];
                              return AppCard(
                                padding: const EdgeInsets.all(AppSpacing.md),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${rule.requiredVisitCount} ziyaret → '
                                            '${_rewardLabel(rule.rewardType)}',
                                            style: AppTypography.bodyMedium,
                                          ),
                                          Text(
                                            rule.isActive ? 'Aktif' : 'Pasif',
                                            style: AppTypography.bodySmall
                                                .copyWith(
                                              color: rule.isActive
                                                  ? AppColors.success
                                                  : AppColors.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Switch(
                                      value: rule.isActive,
                                      onChanged: (_) => _toggleActive(rule),
                                    ),
                                  ],
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
