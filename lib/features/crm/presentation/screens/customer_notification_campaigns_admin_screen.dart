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
import '../../application/use_cases/create_customer_notification_campaign.dart';
import '../../application/use_cases/resolve_notification_campaign_audience.dart';
import '../../domain/notifications/customer_notification_campaign.dart';
import '../../domain/notifications/customer_notification_campaign_status.dart';
import '../providers/crm_dependencies_provider.dart';

/// Administrator notification campaign list + creation, with an
/// audience-size preview — Sprint 5D Part 1. **Never sends anything** —
/// this screen only drafts campaigns and previews who would receive one,
/// per the CRM Notification Foundation's "architecture only" scope.
class CustomerNotificationCampaignsAdminScreen extends ConsumerStatefulWidget {
  const CustomerNotificationCampaignsAdminScreen({
    super.key,
    this.authorizationPolicy,
    this.performedByStaffId = 'manager-1',
  });

  final PosAuthorizationPolicy? authorizationPolicy;
  final String performedByStaffId;

  @override
  ConsumerState<CustomerNotificationCampaignsAdminScreen> createState() =>
      _CustomerNotificationCampaignsAdminScreenState();
}

class _CustomerNotificationCampaignsAdminScreenState
    extends ConsumerState<CustomerNotificationCampaignsAdminScreen> {
  List<CustomerNotificationCampaign>? _campaigns;
  Map<String, int> _audienceSizes = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final campaigns = await ref
        .read(customerNotificationCampaignRepositoryProvider)
        .findAll();
    final resolveAudience = ResolveNotificationCampaignAudience(
      customerRepository: ref.read(customerRepositoryProvider),
    );
    final sizes = <String, int>{};
    for (final campaign in campaigns) {
      sizes[campaign.id] = (await resolveAudience(campaign)).length;
    }
    if (!mounted) return;
    setState(() {
      _campaigns = campaigns;
      _audienceSizes = sizes;
    });
  }

  static String _statusLabel(CustomerNotificationCampaignStatus status) {
    switch (status) {
      case CustomerNotificationCampaignStatus.draft:
        return 'Taslak';
      case CustomerNotificationCampaignStatus.scheduled:
        return 'Zamanlandı';
      case CustomerNotificationCampaignStatus.sent:
        return 'Gönderildi';
      case CustomerNotificationCampaignStatus.cancelled:
        return 'İptal Edildi';
    }
  }

  Future<void> _createCampaign() async {
    final policy = widget.authorizationPolicy;
    if (policy == null) {
      setState(() => _error = 'Yetki politikası tanımlı değil.');
      return;
    }

    final titleController = TextEditingController();
    final bodyController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yeni Kampanya'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: 'Başlık'),
            ),
            TextField(
              controller: bodyController,
              decoration: const InputDecoration(labelText: 'Mesaj'),
              maxLines: 3,
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
            child: const Text('Taslak Oluştur'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await CreateCustomerNotificationCampaign(
        authorizationPolicy: policy,
        idGenerator: ref.read(customerNotificationCampaignIdGeneratorProvider),
        repository: ref.read(customerNotificationCampaignRepositoryProvider),
        auditRepository: ref.read(crmAuditEntryRepositoryProvider),
      )(
        title: titleController.text,
        body: bodyController.text,
        performedByStaffId: widget.performedByStaffId,
        createdAt: ref.read(clockProvider).now(),
      );
      setState(() => _error = null);
      await _load();
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final campaigns = _campaigns;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Bildirim Kampanyaları'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Yeni Kampanya',
            onPressed: _createCampaign,
          ),
        ],
      ),
      body: SafeArea(
        child: campaigns == null
            ? const LoadingView(message: 'Kampanyalar yükleniyor...')
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
                    child: campaigns.isEmpty
                        ? const EmptyView(
                            icon: Icons.campaign_outlined,
                            message: 'Henüz kampanya oluşturulmadı.',
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            itemCount: campaigns.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: AppSpacing.sm),
                            itemBuilder: (context, index) {
                              final campaign = campaigns[index];
                              return AppCard(
                                padding: const EdgeInsets.all(AppSpacing.md),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(campaign.title,
                                        style: AppTypography.bodyMedium),
                                    Text(
                                      '${_statusLabel(campaign.status)} • '
                                      'Hedef kitle: '
                                      '${_audienceSizes[campaign.id] ?? 0} müşteri',
                                      style: AppTypography.bodySmall.copyWith(
                                          color: AppColors.textSecondary),
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
