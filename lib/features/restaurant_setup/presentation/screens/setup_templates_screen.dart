import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../application/use_cases/apply_setup_template.dart';
import '../../domain/setup_template.dart';
import '../../domain/setup_template_application_snapshot.dart';
import '../providers/restaurant_setup_dependencies_provider.dart';

/// Smart Restaurant Setup — template browser — Phase 7
/// (`docs/decisions.md` ADR-024). Lists templates visible to the
/// organization (every public one, plus its own private ones) and
/// applies one, which only records a frozen
/// [SetupTemplateApplicationSnapshot] — never creates real menu/
/// inventory data automatically.
class SetupTemplatesScreen extends ConsumerStatefulWidget {
  const SetupTemplatesScreen({
    super.key,
    required this.organizationId,
    required this.restaurantId,
    required this.branchId,
    this.authorizationPolicy,
    this.performedByStaffId = '',
  });

  final String organizationId;
  final String restaurantId;
  final String branchId;
  final PosAuthorizationPolicy? authorizationPolicy;
  final String performedByStaffId;

  @override
  ConsumerState<SetupTemplatesScreen> createState() =>
      _SetupTemplatesScreenState();
}

class _SetupTemplatesScreenState extends ConsumerState<SetupTemplatesScreen> {
  List<SetupTemplate>? _templates;
  List<SetupTemplateApplicationSnapshot>? _snapshots;
  String? _error;
  String? _info;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final templates = await ref
        .read(setupTemplateRepositoryProvider)
        .findVisibleTo(widget.organizationId);
    final snapshots = await ref
        .read(setupTemplateApplicationSnapshotRepositoryProvider)
        .findByBranchId(widget.branchId);
    if (!mounted) return;
    setState(() {
      _templates = templates;
      _snapshots = snapshots;
    });
  }

  Future<void> _apply(SetupTemplate template) async {
    final policy = widget.authorizationPolicy;
    if (policy == null) {
      setState(() => _error = 'Yetki politikası tanımlı değil.');
      return;
    }
    try {
      await ApplySetupTemplate(
        authorizationPolicy: policy,
        templateRepository: ref.read(setupTemplateRepositoryProvider),
        snapshotRepository:
            ref.read(setupTemplateApplicationSnapshotRepositoryProvider),
        idGenerator:
            ref.read(setupTemplateApplicationSnapshotIdGeneratorProvider),
      )(
        templateId: template.id,
        organizationId: widget.organizationId,
        restaurantId: widget.restaurantId,
        branchId: widget.branchId,
        performedByStaffId: widget.performedByStaffId,
        performedAt: DateTime.now(),
      );
      setState(() {
        _error = null;
        _info = '"${template.name}" önerileri kaydedildi. Kategoriler/'
            'malzemeler/modifier desenleri Menü İçe Aktarma veya ilgili '
            'yönetim ekranlarından manuel olarak oluşturulmalı.';
      });
      await _load();
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final templates = _templates;
    final snapshots = _snapshots;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Akıllı Kurulum Şablonları'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: templates == null || snapshots == null
            ? const LoadingView(message: 'Şablonlar yükleniyor...')
            : templates.isEmpty
                ? const EmptyView(
                    icon: Icons.auto_awesome_outlined,
                    message: 'Görünür bir kurulum şablonu yok.',
                  )
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
                      for (final template in templates)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: AppCard(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(template.name,
                                          style: AppTypography.titleMedium),
                                    ),
                                    if (template.isPublic)
                                      const Icon(Icons.public,
                                          size: 16,
                                          color: AppColors.textSecondary)
                                    else
                                      const Icon(Icons.lock_outline,
                                          size: 16,
                                          color: AppColors.textSecondary),
                                  ],
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  '${template.category.name} · v${template.revision} · '
                                  '${template.categorySuggestions.length} kategori, '
                                  '${template.ingredientReferences.length} malzeme, '
                                  '${template.modifierPatterns.length} modifier deseni',
                                  style: AppTypography.bodySmall
                                      .copyWith(color: AppColors.textSecondary),
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                OutlinedButton(
                                  onPressed: () => _apply(template),
                                  child: const Text('Bu Şablonu Uygula'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (snapshots.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.md),
                        const Text('Uygulanan Şablonlar',
                            style: AppTypography.titleMedium),
                        for (final snapshot in snapshots)
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.check_circle_outline),
                            title: Text(
                                '${snapshot.templateId} (v${snapshot.templateRevisionApplied})'),
                            subtitle: Text('${snapshot.appliedAt}'),
                          ),
                      ],
                    ],
                  ),
      ),
    );
  }
}
