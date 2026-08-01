import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../application/use_cases/review_translation.dart';
import '../../application/use_cases/set_fallback_language.dart';
import '../../application/use_cases/set_language_enabled.dart';
import '../../application/use_cases/set_translation_content.dart';
import '../../domain/localization/localization_config.dart';
import '../../domain/localization/localization_scope_type.dart';
import '../../domain/localization/supported_language.dart';
import '../../domain/localization/translation_entry.dart';
import '../../domain/localization/translation_status.dart';
import '../providers/admin_dependencies_provider.dart';

/// Localization administration foundation — Phase 6N
/// (`docs/decisions.md` ADR-023). "Build architecture and
/// administration foundation only" — this screen manages which
/// languages are enabled/fallback for the current branch, and lets a
/// staff member manually author/review translation content by content
/// key. No AI translation call, no bulk import, no customer-facing
/// language switch — those are explicitly out of scope.
class LocalizationAdminScreen extends ConsumerStatefulWidget {
  const LocalizationAdminScreen({
    super.key,
    required this.branchId,
    this.authorizationPolicy,
    this.performedByStaffId = '',
  });

  final String branchId;
  final PosAuthorizationPolicy? authorizationPolicy;
  final String performedByStaffId;

  @override
  ConsumerState<LocalizationAdminScreen> createState() =>
      _LocalizationAdminScreenState();
}

class _LocalizationAdminScreenState
    extends ConsumerState<LocalizationAdminScreen> {
  LocalizationConfig? _config;
  String? _error;
  final _contentKeyController = TextEditingController();
  List<TranslationEntry>? _translationEntries;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadConfig());
  }

  @override
  void dispose() {
    _contentKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final config = await ref
        .read(localizationConfigRepositoryProvider)
        .findByScope(LocalizationScopeType.branch, widget.branchId);
    if (!mounted) return;
    setState(() => _config = config ??
        LocalizationConfig(
          id: '',
          scopeType: LocalizationScopeType.branch,
          scopeId: widget.branchId,
          createdAt: DateTime.now(),
          revision: 0,
        ));
  }

  Future<void> _toggleLanguage(SupportedLanguage language, bool enabled) {
    return _requirePolicyAsync((policy) async {
      await SetLanguageEnabled(
        authorizationPolicy: policy,
        idGenerator: ref.read(localizationConfigIdGeneratorProvider),
        repository: ref.read(localizationConfigRepositoryProvider),
        auditRepository: ref.read(adminAuditEntryRepositoryProvider),
      )(
        scopeType: LocalizationScopeType.branch,
        scopeId: widget.branchId,
        language: language,
        enabled: enabled,
        performedByStaffId: widget.performedByStaffId,
        performedAt: DateTime.now(),
      );
      await _loadConfig();
    });
  }

  Future<void> _setFallback(SupportedLanguage language) {
    return _requirePolicyAsync((policy) async {
      await SetFallbackLanguage(
        authorizationPolicy: policy,
        repository: ref.read(localizationConfigRepositoryProvider),
        auditRepository: ref.read(adminAuditEntryRepositoryProvider),
      )(
        scopeType: LocalizationScopeType.branch,
        scopeId: widget.branchId,
        language: language,
        performedByStaffId: widget.performedByStaffId,
        performedAt: DateTime.now(),
      );
      await _loadConfig();
    });
  }

  Future<void> _requirePolicyAsync(
    Future<void> Function(PosAuthorizationPolicy policy) run,
  ) async {
    final policy = widget.authorizationPolicy;
    if (policy == null) {
      setState(() => _error = 'Yetki politikası tanımlı değil.');
      return;
    }
    try {
      await run(policy);
      setState(() => _error = null);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _loadTranslations() async {
    final key = _contentKeyController.text.trim();
    if (key.isEmpty) return;
    final entries = await ref
        .read(translationEntryRepositoryProvider)
        .findByContentKey(key);
    if (!mounted) return;
    setState(() => _translationEntries = entries);
  }

  Future<void> _editTranslation(SupportedLanguage language) async {
    final key = _contentKeyController.text.trim();
    if (key.isEmpty) return;
    final controller = TextEditingController(
      text: _translationEntries
          ?.where((e) => e.language == language)
          .map((e) => e.content ?? '')
          .firstOrNull,
    );
    final content = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${language.nativeLabel} çevirisi'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    if (content == null || content.trim().isEmpty) return;

    await _requirePolicyAsync((policy) async {
      await SetTranslationContent(
        authorizationPolicy: policy,
        idGenerator: ref.read(translationEntryIdGeneratorProvider),
        repository: ref.read(translationEntryRepositoryProvider),
        auditRepository: ref.read(adminAuditEntryRepositoryProvider),
      )(
        contentKey: key,
        language: language,
        content: content.trim(),
        isMachineGenerated: false,
        performedByStaffId: widget.performedByStaffId,
        performedAt: DateTime.now(),
      );
      await _loadTranslations();
    });
  }

  Future<void> _reviewTranslation(
    TranslationEntry entry,
    TranslationStatus status,
  ) async {
    await _requirePolicyAsync((policy) async {
      await ReviewTranslation(
        authorizationPolicy: policy,
        repository: ref.read(translationEntryRepositoryProvider),
        auditRepository: ref.read(adminAuditEntryRepositoryProvider),
      )(
        translationEntryId: entry.id,
        newStatus: status,
        performedByStaffId: widget.performedByStaffId,
        performedAt: DateTime.now(),
      );
      await _loadTranslations();
    });
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Yerelleştirme'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: config == null
            ? const LoadingView(message: 'Yerelleştirme ayarları yükleniyor...')
            : ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  if (_error != null) ...[
                    Text(_error!,
                        style: AppTypography.bodySmall
                            .copyWith(color: AppColors.error)),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  const Text('Diller', style: AppTypography.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  AppCard(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      children: [
                        for (final language in SupportedLanguage.values)
                          CheckboxListTile(
                            value: config.enabledLanguages.contains(language),
                            onChanged: language == SupportedLanguage.master
                                ? null
                                : (value) =>
                                    _toggleLanguage(language, value ?? false),
                            title: Text(
                              '${language.nativeLabel}'
                              '${language.isRtl ? ' (RTL)' : ''}'
                              '${language == SupportedLanguage.master ? ' — ana dil' : ''}'
                              '${language == config.fallbackLanguage ? ' — yedek dil' : ''}',
                            ),
                            secondary:
                                config.enabledLanguages.contains(language) &&
                                        language != config.fallbackLanguage
                                    ? TextButton(
                                        onPressed: () => _setFallback(language),
                                        child: const Text('Yedek Yap'),
                                      )
                                    : null,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const Text('Çeviriler', style: AppTypography.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  AppCard(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _contentKeyController,
                                decoration: const InputDecoration(
                                  hintText:
                                      'İçerik anahtarı (ör. menu.item.1.name)',
                                  border: OutlineInputBorder(),
                                ),
                                onSubmitted: (_) => _loadTranslations(),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            ElevatedButton(
                              onPressed: _loadTranslations,
                              child: const Text('Yükle'),
                            ),
                          ],
                        ),
                        if (_translationEntries != null) ...[
                          const SizedBox(height: AppSpacing.md),
                          for (final language in config.enabledLanguages)
                            _TranslationRow(
                              language: language,
                              entry: _translationEntries!
                                  .where((e) => e.language == language)
                                  .firstOrNull,
                              onEdit: () => _editTranslation(language),
                              onReview: (status) {
                                final entry = _translationEntries!
                                    .where((e) => e.language == language)
                                    .firstOrNull;
                                if (entry != null) {
                                  _reviewTranslation(entry, status);
                                }
                              },
                            ),
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

class _TranslationRow extends StatelessWidget {
  const _TranslationRow({
    required this.language,
    required this.entry,
    required this.onEdit,
    required this.onReview,
  });

  final SupportedLanguage language;
  final TranslationEntry? entry;
  final VoidCallback onEdit;
  final void Function(TranslationStatus status) onReview;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(language.nativeLabel, style: AppTypography.bodyMedium),
          ),
          Expanded(
            child: Text(
              entry?.content ?? '(çeviri yok)',
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
            ),
          ),
          if (entry != null)
            Text(
              '${entry!.status.name}'
              '${entry!.isMachineGenerated ? ' · makine' : ''}'
              '${entry!.isManuallyEdited ? ' · elle düzenlendi' : ''}',
              style: AppTypography.bodySmall.copyWith(color: AppColors.primary),
            ),
          TextButton(onPressed: onEdit, child: const Text('Düzenle')),
          if (entry != null && entry!.status != TranslationStatus.approved)
            TextButton(
              onPressed: () => onReview(TranslationStatus.approved),
              child: const Text('Onayla'),
            ),
        ],
      ),
    );
  }
}
