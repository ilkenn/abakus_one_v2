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
import '../../application/use_cases/respond_to_customer_feedback.dart';
import '../../application/use_cases/update_customer_feedback_status.dart';
import '../../domain/customer_feedback.dart';
import '../../domain/feedback_status.dart';
import '../providers/feedback_dependencies_provider.dart';

/// Administrator feedback ticket list, response, and status triage —
/// Sprint 5D Part 1.
class FeedbackAdminScreen extends ConsumerStatefulWidget {
  const FeedbackAdminScreen({
    super.key,
    required this.branchId,
    this.authorizationPolicy,
    this.performedByStaffId = 'manager-1',
  });

  final String branchId;
  final PosAuthorizationPolicy? authorizationPolicy;
  final String performedByStaffId;

  @override
  ConsumerState<FeedbackAdminScreen> createState() =>
      _FeedbackAdminScreenState();
}

class _FeedbackAdminScreenState extends ConsumerState<FeedbackAdminScreen> {
  List<CustomerFeedback>? _tickets;
  Map<String, FeedbackStatus> _statusByTicket = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final tickets = await ref
        .read(customerFeedbackRepositoryProvider)
        .findByBranchId(widget.branchId);
    final statusEventRepository =
        ref.read(customerFeedbackStatusEventRepositoryProvider);
    final statuses = <String, FeedbackStatus>{};
    for (final ticket in tickets) {
      final history = await statusEventRepository.findByFeedbackId(ticket.id);
      statuses[ticket.id] =
          history.isEmpty ? FeedbackStatus.open : history.last.status;
    }
    if (!mounted) return;
    setState(() {
      _tickets = tickets;
      _statusByTicket = statuses;
    });
  }

  static String _statusLabel(FeedbackStatus status) {
    switch (status) {
      case FeedbackStatus.open:
        return 'Açık';
      case FeedbackStatus.inReview:
        return 'İnceleniyor';
      case FeedbackStatus.resolved:
        return 'Çözüldü';
      case FeedbackStatus.closed:
        return 'Kapatıldı';
    }
  }

  Future<void> _respond(CustomerFeedback ticket) async {
    final policy = widget.authorizationPolicy;
    if (policy == null) {
      setState(() => _error = 'Yetki politikası tanımlı değil.');
      return;
    }
    final responseController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(ticket.subject),
        content: TextField(
          controller: responseController,
          decoration: const InputDecoration(labelText: 'Yanıt'),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Gönder'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await RespondToCustomerFeedback(
        clock: ref.read(clockProvider),
        authorizationPolicy: policy,
        idGenerator: ref.read(customerFeedbackResponseIdGeneratorProvider),
        feedbackRepository: ref.read(customerFeedbackRepositoryProvider),
        responseRepository:
            ref.read(customerFeedbackResponseRepositoryProvider),
      )(
        feedbackId: ticket.id,
        responseText: responseController.text,
        performedByStaffId: widget.performedByStaffId,
      );
      setState(() => _error = null);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _updateStatus(
      CustomerFeedback ticket, FeedbackStatus status) async {
    final policy = widget.authorizationPolicy;
    if (policy == null) {
      setState(() => _error = 'Yetki politikası tanımlı değil.');
      return;
    }
    try {
      await UpdateCustomerFeedbackStatus(
        clock: ref.read(clockProvider),
        authorizationPolicy: policy,
        idGenerator: ref.read(customerFeedbackStatusEventIdGeneratorProvider),
        feedbackRepository: ref.read(customerFeedbackRepositoryProvider),
        statusEventRepository:
            ref.read(customerFeedbackStatusEventRepositoryProvider),
      )(
        feedbackId: ticket.id,
        status: status,
        performedByStaffId: widget.performedByStaffId,
      );
      await _load();
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final tickets = _tickets;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Geri Bildirim Yönetimi'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Yenile',
            onPressed: _load,
          ),
        ],
      ),
      body: SafeArea(
        child: tickets == null
            ? const LoadingView(message: 'Geri bildirimler yükleniyor...')
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
                    child: tickets.isEmpty
                        ? const EmptyView(
                            icon: Icons.feedback_outlined,
                            message: 'Henüz geri bildirim yok.',
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            itemCount: tickets.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: AppSpacing.sm),
                            itemBuilder: (context, index) {
                              final ticket = tickets[index];
                              final status = _statusByTicket[ticket.id] ??
                                  FeedbackStatus.open;
                              return AppCard(
                                padding: const EdgeInsets.all(AppSpacing.md),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(ticket.subject,
                                        style: AppTypography.bodyMedium),
                                    Text(ticket.body,
                                        style: AppTypography.bodySmall.copyWith(
                                            color: AppColors.textSecondary)),
                                    const SizedBox(height: AppSpacing.xs),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        DropdownButton<FeedbackStatus>(
                                          value: status,
                                          items: [
                                            for (final s
                                                in FeedbackStatus.values)
                                              DropdownMenuItem(
                                                value: s,
                                                child: Text(_statusLabel(s)),
                                              ),
                                          ],
                                          onChanged: (value) {
                                            if (value != null) {
                                              _updateStatus(ticket, value);
                                            }
                                          },
                                        ),
                                        TextButton(
                                          onPressed: () => _respond(ticket),
                                          child: const Text('Yanıtla'),
                                        ),
                                      ],
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
