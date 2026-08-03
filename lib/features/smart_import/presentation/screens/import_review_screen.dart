import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../domain/import_draft.dart';
import '../../domain/import_issue.dart';
import '../../domain/import_job.dart';
import '../../domain/import_review_decision.dart';
import '../../domain/import_status.dart';
import '../providers/smart_import_dependencies_provider.dart';

/// The Import Review & Approval workspace — Phase 7
/// (`docs/decisions.md` ADR-024). Shows every parsed category/product
/// with its confidence score and issues, lets the reviewer approve or
/// reject each one, then commits — "the user must approve before
/// authoritative records are created." Displays an honest summary
/// (counts only, never a fabricated percentage) and, once committed,
/// offers rollback.
class ImportReviewScreen extends ConsumerStatefulWidget {
  const ImportReviewScreen({
    super.key,
    required this.importJobId,
    this.performedByStaffId = '',
  });

  final String importJobId;
  final String performedByStaffId;

  @override
  ConsumerState<ImportReviewScreen> createState() => _ImportReviewScreenState();
}

class _ImportReviewScreenState extends ConsumerState<ImportReviewScreen> {
  ImportJob? _job;
  ImportDraft? _draft;
  final Set<String> _approvedTempIds = {};
  String? _error;
  String? _info;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final job = await ref
        .read(importJobRepositoryProvider)
        .findById(widget.importJobId);
    final draft = await ref
        .read(importDraftRepositoryProvider)
        .findByImportJobId(widget.importJobId);
    if (!mounted) return;
    setState(() {
      _job = job;
      _draft = draft;
    });
  }

  Future<void> _approveAndCommit() async {
    final draft = _draft;
    if (draft == null) return;
    try {
      final decisions = [
        for (final category in draft.parsedMenu.categories)
          ImportReviewDecision(
            tempId: category.tempId,
            outcome: _approvedTempIds.contains(category.tempId)
                ? ImportReviewOutcome.approved
                : ImportReviewOutcome.rejected,
          ),
        for (final product in draft.parsedMenu.products)
          ImportReviewDecision(
            tempId: product.tempId,
            outcome: _approvedTempIds.contains(product.tempId)
                ? ImportReviewOutcome.approved
                : ImportReviewOutcome.rejected,
          ),
      ];

      final approval = await ref.read(approveImportDraftProvider).call(
            importJobId: widget.importJobId,
            decisions: decisions,
            performedByStaffId: widget.performedByStaffId,
            performedAt: DateTime.now(),
          );

      final result = await ref.read(commitImportDraftProvider).call(
            importJobId: widget.importJobId,
            approval: approval,
            performedAt: DateTime.now(),
          );

      setState(() {
        _error = null;
        _info = '${result.createdCategoryIds.length} kategori, '
            '${result.createdProductIds.length} ürün oluşturuldu. '
            '${result.skippedCount} atlandı, ${result.errorCount} hata.';
      });
      await _load();
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _rollback() async {
    setState(() => _error = 'Bu işlemi geri almak için Cihaz Kaydı '
        'benzeri bir "Geri Al" akışı Denetim ekranından tetiklenmelidir.');
  }

  @override
  Widget build(BuildContext context) {
    final job = _job;
    final draft = _draft;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('İçe Aktarma İncelemesi'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: job == null || draft == null
            ? const LoadingView(message: 'Taslak yükleniyor...')
            : ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  if (_error != null) ...[
                    Text(_error!,
                        style: AppTypography.bodySmall
                            .copyWith(color: AppColors.error)),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  if (_info != null) ...[
                    Text(_info!,
                        style: AppTypography.bodySmall
                            .copyWith(color: AppColors.success)),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  Text(
                    'Özet: ${draft.parsedMenu.categories.length} kategori, '
                    '${draft.parsedMenu.products.length} ürün, '
                    '${draft.parsedMenu.issues.length} bulgu incelenmeli.',
                    style: AppTypography.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const Text('Kategoriler', style: AppTypography.titleMedium),
                  for (final category in draft.parsedMenu.categories)
                    CheckboxListTile(
                      value: _approvedTempIds.contains(category.tempId),
                      onChanged: job.status == ImportStatus.committed
                          ? null
                          : (value) => setState(() {
                                if (value ?? false) {
                                  _approvedTempIds.add(category.tempId);
                                } else {
                                  _approvedTempIds.remove(category.tempId);
                                }
                              }),
                      title: Text(category.name),
                    ),
                  const SizedBox(height: AppSpacing.md),
                  const Text('Ürünler', style: AppTypography.titleMedium),
                  for (final product in draft.parsedMenu.products)
                    AppCard(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      child: CheckboxListTile(
                        value: _approvedTempIds.contains(product.tempId),
                        onChanged: job.status == ImportStatus.committed
                            ? null
                            : (value) => setState(() {
                                  if (value ?? false) {
                                    _approvedTempIds.add(product.tempId);
                                  } else {
                                    _approvedTempIds.remove(product.tempId);
                                  }
                                }),
                        title: Text(product.name),
                        subtitle: Text(
                          '${product.price ?? '?'} ${product.currencyCode ?? ''} · '
                          'Güven: %${product.confidence.score} '
                          '(${product.confidence.reasons.join(', ')})',
                          style: AppTypography.bodySmall
                              .copyWith(color: AppColors.textSecondary),
                        ),
                      ),
                    ),
                  if (draft.parsedMenu.issues.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    const Text('Bulgular', style: AppTypography.titleMedium),
                    for (final issue in draft.parsedMenu.issues)
                      ListTile(
                        dense: true,
                        leading: Icon(
                          issue.severity == ImportIssueSeverity.error
                              ? Icons.error_outline
                              : issue.severity == ImportIssueSeverity.warning
                                  ? Icons.warning_amber_outlined
                                  : Icons.info_outline,
                          color: issue.severity == ImportIssueSeverity.error
                              ? AppColors.error
                              : AppColors.textSecondary,
                        ),
                        title: Text(issue.message),
                      ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  if (job.status == ImportStatus.committed)
                    OutlinedButton(
                      onPressed: _rollback,
                      child: const Text('Geri Al'),
                    )
                  else
                    ElevatedButton(
                      onPressed: _approveAndCommit,
                      child: const Text('Seçilenleri Onayla ve Aktar'),
                    ),
                ],
              ),
      ),
    );
  }
}
