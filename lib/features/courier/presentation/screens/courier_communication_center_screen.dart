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
import '../../application/use_cases/record_courier_event.dart';
import '../../application/use_cases/send_courier_message.dart';
import '../../domain/communication/courier_message.dart';
import '../../domain/communication/courier_message_type.dart';
import '../../domain/communication/courier_ready_message_template.dart';
import '../providers/courier_dependencies_provider.dart';

/// Manager-facing Communication Center — Sprint 5C Part 8. Real message
/// history + compose, for direct/broadcast/emergency messages. See
/// [CourierMessage]'s own doc comment for this app's honest same-process
/// real-time boundary.
class CourierCommunicationCenterScreen extends ConsumerStatefulWidget {
  const CourierCommunicationCenterScreen({
    super.key,
    required this.branchId,
    this.authorizationPolicy,
    this.performedByStaffId = 'manager-1',
  });

  final String branchId;
  final PosAuthorizationPolicy? authorizationPolicy;
  final String performedByStaffId;

  @override
  ConsumerState<CourierCommunicationCenterScreen> createState() =>
      _CourierCommunicationCenterScreenState();
}

class _CourierCommunicationCenterScreenState
    extends ConsumerState<CourierCommunicationCenterScreen> {
  List<CourierMessage>? _messages;
  CourierMessageType _composeType = CourierMessageType.direct;
  final _recipientController = TextEditingController();
  final _bodyController = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _recipientController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final messages = await ref
        .read(courierMessageRepositoryProvider)
        .findByBranchId(widget.branchId);
    final sorted = [...messages]..sort((a, b) => b.sentAt.compareTo(a.sentAt));
    if (!mounted) return;
    setState(() => _messages = sorted);
  }

  Future<void> _send() async {
    final policy = widget.authorizationPolicy;
    if (policy == null) {
      setState(() => _error = 'Yetki politikası tanımlı değil.');
      return;
    }
    if (_bodyController.text.trim().isEmpty) {
      setState(() => _error = 'Mesaj boş olamaz.');
      return;
    }
    final recipient = _recipientController.text.trim();
    if (_composeType == CourierMessageType.direct && recipient.isEmpty) {
      setState(() => _error = 'Doğrudan mesaj için kurye seçin.');
      return;
    }

    try {
      await SendCourierMessage(
        clock: ref.read(clockProvider),
        authorizationPolicy: policy,
        idGenerator: ref.read(courierMessageIdGeneratorProvider),
        repository: ref.read(courierMessageRepositoryProvider),
        auditRepository:
            ref.read(courierOperationalAuditEntryRepositoryProvider),
        recordCourierEvent: RecordCourierEvent(
          idGenerator: ref.read(courierEventIdGeneratorProvider),
          eventRepository: ref.read(courierEventRepositoryProvider),
          eventPublisher: ref.read(courierEventPublisherProvider),
        ),
      )(
        branchId: widget.branchId,
        type: _composeType,
        recipientCourierId:
            _composeType == CourierMessageType.direct ? recipient : null,
        body: _bodyController.text.trim(),
        performedByStaffId: widget.performedByStaffId,
      );
      _bodyController.clear();
      setState(() => _error = null);
      await _load();
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  static String _typeLabel(CourierMessageType type) {
    switch (type) {
      case CourierMessageType.direct:
        return 'Özel';
      case CourierMessageType.broadcast:
        return 'Toplu';
      case CourierMessageType.emergency:
        return 'ACİL';
    }
  }

  static Color _typeColor(CourierMessageType type) {
    switch (type) {
      case CourierMessageType.direct:
        return AppColors.primary;
      case CourierMessageType.broadcast:
        return AppColors.warning;
      case CourierMessageType.emergency:
        return AppColors.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = _messages;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('İletişim Merkezi'),
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
        child: messages == null
            ? const LoadingView(message: 'Mesajlar yükleniyor...')
            : Column(
                children: [
                  Expanded(
                    child: messages.isEmpty
                        ? const EmptyView(
                            icon: Icons.chat_bubble_outline,
                            message: 'Henüz mesaj gönderilmedi.',
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            itemCount: messages.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: AppSpacing.sm),
                            itemBuilder: (context, index) {
                              final message = messages[index];
                              return AppCard(
                                padding: const EdgeInsets.all(AppSpacing.md),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: AppSpacing.xs,
                                              vertical: 2),
                                          decoration: BoxDecoration(
                                            color: _typeColor(message.type)
                                                .withValues(alpha: 0.15),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            _typeLabel(message.type),
                                            style: AppTypography.bodySmall
                                                .copyWith(
                                                    color: _typeColor(
                                                        message.type)),
                                          ),
                                        ),
                                        const SizedBox(width: AppSpacing.sm),
                                        Text(
                                          message.recipientCourierId ??
                                              'Tüm kuryeler',
                                          style: AppTypography.bodySmall
                                              .copyWith(
                                                  color:
                                                      AppColors.textSecondary),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: AppSpacing.xs),
                                    Text(message.body,
                                        style: AppTypography.bodyMedium),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                  AppCard(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_error != null) ...[
                          Text(_error!,
                              style: AppTypography.bodySmall
                                  .copyWith(color: AppColors.error)),
                          const SizedBox(height: AppSpacing.xs),
                        ],
                        Wrap(
                          spacing: AppSpacing.xs,
                          children: [
                            for (final type in CourierMessageType.values)
                              ChoiceChip(
                                label: Text(_typeLabel(type)),
                                selected: _composeType == type,
                                onSelected: (_) =>
                                    setState(() => _composeType = type),
                              ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        if (_composeType == CourierMessageType.direct)
                          TextField(
                            controller: _recipientController,
                            decoration:
                                const InputDecoration(labelText: 'Kurye ID'),
                          ),
                        Wrap(
                          spacing: AppSpacing.xs,
                          children: [
                            for (final template
                                in CourierReadyMessageTemplate.values)
                              ActionChip(
                                label: Text(template.text),
                                onPressed: () =>
                                    _bodyController.text = template.text,
                              ),
                          ],
                        ),
                        TextField(
                          controller: _bodyController,
                          decoration: const InputDecoration(labelText: 'Mesaj'),
                          maxLines: 2,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Align(
                          alignment: Alignment.centerRight,
                          child: ElevatedButton(
                            onPressed: _send,
                            child: const Text('Gönder'),
                          ),
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
