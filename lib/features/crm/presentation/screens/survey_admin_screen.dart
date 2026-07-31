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
import '../../application/use_cases/create_survey.dart';
import '../../domain/surveys/survey.dart';
import '../../domain/surveys/survey_question.dart';
import '../../domain/surveys/survey_question_type.dart';
import '../providers/crm_dependencies_provider.dart';

/// Administrator survey list + creation — Sprint 5D Part 1. Creation here
/// composes a single starting question (the underlying architecture,
/// `CreateSurvey`, already accepts an arbitrary question list — a
/// multi-question composer UI is deferred, "clean screens, not UI
/// polishing").
class SurveyAdminScreen extends ConsumerStatefulWidget {
  const SurveyAdminScreen({
    super.key,
    this.authorizationPolicy,
    this.performedByStaffId = 'manager-1',
  });

  final PosAuthorizationPolicy? authorizationPolicy;
  final String performedByStaffId;

  @override
  ConsumerState<SurveyAdminScreen> createState() => _SurveyAdminScreenState();
}

class _SurveyAdminScreenState extends ConsumerState<SurveyAdminScreen> {
  List<Survey>? _surveys;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final surveys = await ref.read(surveyRepositoryProvider).findAll();
    if (!mounted) return;
    setState(() => _surveys = surveys);
  }

  static String _typeLabel(SurveyQuestionType type) {
    switch (type) {
      case SurveyQuestionType.rating:
        return 'Puanlama';
      case SurveyQuestionType.stars:
        return 'Yıldız';
      case SurveyQuestionType.emoji:
        return 'Emoji';
      case SurveyQuestionType.multipleChoice:
        return 'Çoktan Seçmeli';
      case SurveyQuestionType.text:
        return 'Metin';
      case SurveyQuestionType.boolean:
        return 'Evet/Hayır';
    }
  }

  Future<void> _createSurvey() async {
    final policy = widget.authorizationPolicy;
    if (policy == null) {
      setState(() => _error = 'Yetki politikası tanımlı değil.');
      return;
    }

    final titleController = TextEditingController();
    final promptController = TextEditingController();
    var type = SurveyQuestionType.rating;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Yeni Anket'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: 'Anket başlığı'),
              ),
              TextField(
                controller: promptController,
                decoration: const InputDecoration(labelText: 'İlk soru'),
              ),
              DropdownButton<SurveyQuestionType>(
                value: type,
                isExpanded: true,
                items: [
                  for (final t in SurveyQuestionType.values)
                    DropdownMenuItem(value: t, child: Text(_typeLabel(t))),
                ],
                onChanged: (value) =>
                    setDialogState(() => type = value ?? type),
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

    try {
      await CreateSurvey(
        authorizationPolicy: policy,
        idGenerator: ref.read(surveyIdGeneratorProvider),
        repository: ref.read(surveyRepositoryProvider),
      )(
        title: titleController.text,
        questions: [
          SurveyQuestion(
            id: 'q1',
            type: type,
            prompt: promptController.text,
            options: type == SurveyQuestionType.multipleChoice
                ? const [
                    SurveyQuestionOption(id: 'a', label: 'Seçenek A'),
                    SurveyQuestionOption(id: 'b', label: 'Seçenek B'),
                  ]
                : const [],
          ),
        ],
        activeFrom: ref.read(clockProvider).now(),
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
    final surveys = _surveys;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Anketler'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Yeni Anket',
            onPressed: _createSurvey,
          ),
        ],
      ),
      body: SafeArea(
        child: surveys == null
            ? const LoadingView(message: 'Anketler yükleniyor...')
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
                    child: surveys.isEmpty
                        ? const EmptyView(
                            icon: Icons.poll_outlined,
                            message: 'Henüz anket oluşturulmadı.',
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            itemCount: surveys.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: AppSpacing.sm),
                            itemBuilder: (context, index) {
                              final survey = surveys[index];
                              return AppCard(
                                padding: const EdgeInsets.all(AppSpacing.md),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(survey.title,
                                        style: AppTypography.bodyMedium),
                                    Text(
                                      '${survey.questions.length} soru • '
                                      '${survey.isActive ? 'Aktif' : 'Pasif'}',
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
