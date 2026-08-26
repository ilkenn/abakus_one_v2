import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/clock_provider.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../application/use_cases/submit_customer_feedback.dart';
import '../../domain/feedback_category.dart';
import '../providers/feedback_dependencies_provider.dart';

/// Customer-facing feedback submission — Sprint 5D Part 1.
class CustomerFeedbackScreen extends ConsumerStatefulWidget {
  const CustomerFeedbackScreen({
    super.key,
    required this.branchId,
    this.customerId,
  });

  final String branchId;
  final String? customerId;

  @override
  ConsumerState<CustomerFeedbackScreen> createState() =>
      _CustomerFeedbackScreenState();
}

class _CustomerFeedbackScreenState
    extends ConsumerState<CustomerFeedbackScreen> {
  FeedbackCategory _category = FeedbackCategory.suggestion;
  final _subjectController = TextEditingController();
  final _bodyController = TextEditingController();
  String? _error;
  bool _submitted = false;

  @override
  void dispose() {
    _subjectController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  static String _categoryLabel(FeedbackCategory category) {
    switch (category) {
      case FeedbackCategory.suggestion:
        return 'Öneri';
      case FeedbackCategory.complaint:
        return 'Şikayet';
      case FeedbackCategory.thankYou:
        return 'Teşekkür';
      case FeedbackCategory.menuSuggestion:
        return 'Menü Önerisi';
      case FeedbackCategory.bugReport:
        return 'Hata Bildirimi';
      case FeedbackCategory.deliveryIssue:
        return 'Teslimat Sorunu';
      case FeedbackCategory.restaurantExperience:
        return 'Restoran Deneyimi';
      case FeedbackCategory.staffFeedback:
        return 'Personel Geri Bildirimi';
      case FeedbackCategory.generalFeedback:
        return 'Genel Geri Bildirim';
    }
  }

  Future<void> _submit() async {
    if (_subjectController.text.trim().isEmpty) {
      setState(() => _error = 'Konu boş olamaz.');
      return;
    }
    if (_bodyController.text.trim().isEmpty) {
      setState(() => _error = 'Mesaj boş olamaz.');
      return;
    }

    try {
      await SubmitCustomerFeedback(
        clock: ref.read(clockProvider),
        feedbackIdGenerator: ref.read(customerFeedbackIdGeneratorProvider),
        statusEventIdGenerator:
            ref.read(customerFeedbackStatusEventIdGeneratorProvider),
        feedbackRepository: ref.read(customerFeedbackRepositoryProvider),
        statusEventRepository:
            ref.read(customerFeedbackStatusEventRepositoryProvider),
      )(
        customerId: widget.customerId,
        branchId: widget.branchId,
        category: _category,
        subject: _subjectController.text.trim(),
        body: _bodyController.text.trim(),
      );
      setState(() {
        _error = null;
        _submitted = true;
      });
    } catch (e) {
      setState(() => _error = ErrorMapper.map(e).message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Geri Bildirim'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: _submitted
            ? const Center(
                child: Text('Geri bildiriminiz için teşekkür ederiz.',
                    style: AppTypography.bodyLarge),
              )
            : ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
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
                            for (final category in FeedbackCategory.values)
                              ChoiceChip(
                                label: Text(_categoryLabel(category)),
                                selected: _category == category,
                                onSelected: (_) =>
                                    setState(() => _category = category),
                              ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        TextField(
                          controller: _subjectController,
                          decoration: const InputDecoration(labelText: 'Konu'),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        TextField(
                          controller: _bodyController,
                          decoration: const InputDecoration(labelText: 'Mesaj'),
                          maxLines: 4,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Align(
                          alignment: Alignment.centerRight,
                          child: ElevatedButton(
                            onPressed: _submit,
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
