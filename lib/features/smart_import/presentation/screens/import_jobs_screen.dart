import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../application/use_cases/normalize_and_analyze_parsed_menu.dart';
import '../../domain/import_job.dart';
import '../../domain/import_source.dart';
import '../../domain/import_source_type.dart';
import '../providers/smart_import_dependencies_provider.dart';
import 'import_review_screen.dart';

const _sourceTypeLabels = {
  ImportSourceType.csv: 'CSV',
  ImportSourceType.structuredJson: 'JSON',
  ImportSourceType.manualPaste: 'Elle Yapıştırma (CSV biçimi)',
  ImportSourceType.pdf: 'PDF (sağlayıcı gerekli)',
  ImportSourceType.excel: 'Excel (sağlayıcı gerekli)',
  ImportSourceType.websiteUrl: 'Web Sitesi URL (sağlayıcı gerekli)',
  ImportSourceType.qrMenuUrl: 'QR Menü URL (sağlayıcı gerekli)',
  ImportSourceType.marketplaceMenuUrl: 'Pazaryeri Menü URL (sağlayıcı gerekli)',
  ImportSourceType.menuImagePhoto: 'Menü Fotoğrafı / OCR (sağlayıcı gerekli)',
};

/// Smart Import entry screen — Phase 7 (`docs/decisions.md` ADR-024).
/// Lists every [ImportJob] for the branch and starts a new one.
/// "Source -> Parse -> Normalize -> Analyze -> Draft" runs immediately
/// on creation for locally-parseable sources
/// (`ImportSourceType.supportsDeterministicLocalParsing`) so the
/// reviewer lands straight on `ImportReviewScreen`; unsupported source
/// types are still creatable (so the honest "provider required" failure
/// is visible in the job list) but never produce a fake draft.
class ImportJobsScreen extends ConsumerStatefulWidget {
  const ImportJobsScreen({
    super.key,
    required this.organizationId,
    required this.restaurantId,
    required this.branchId,
    this.performedByStaffId = '',
  });

  final String organizationId;
  final String restaurantId;
  final String branchId;
  final String performedByStaffId;

  @override
  ConsumerState<ImportJobsScreen> createState() => _ImportJobsScreenState();
}

class _ImportJobsScreenState extends ConsumerState<ImportJobsScreen> {
  List<ImportJob>? _jobs;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final jobs = List<ImportJob>.of(
      await ref
          .read(importJobRepositoryProvider)
          .findByBranchId(widget.branchId),
    )..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (!mounted) return;
    setState(() => _jobs = jobs);
  }

  Future<void> _startImport() async {
    var selectedType = ImportSourceType.csv;
    final controller = TextEditingController();
    final result = await showDialog<(ImportSourceType, String)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Yeni İçe Aktarma'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButton<ImportSourceType>(
                  value: selectedType,
                  isExpanded: true,
                  items: [
                    for (final type in ImportSourceType.values)
                      DropdownMenuItem(
                        value: type,
                        child: Text(_sourceTypeLabels[type] ?? type.name),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => selectedType = value);
                    }
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                if (!selectedType.supportsDeterministicLocalParsing)
                  Text(
                    'Bu kaynak türü için henüz bir sağlayıcı bağlanmadı — '
                    'iş oluşturulur ancak ayrıştırma başarısız olarak '
                    'işaretlenir.',
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.error),
                  )
                else
                  TextField(
                    controller: controller,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      hintText: 'category,name,description,price,currency\n'
                          'Bowl,Tavuklu Bowl,Izgara tavuk,189.90,TRY',
                      border: OutlineInputBorder(),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.of(context).pop((selectedType, controller.text)),
              child: const Text('Oluştur ve Ayrıştır'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;

    final (type, rawText) = result;
    try {
      final job = await ref.read(createImportJobProvider).call(
            organizationId: widget.organizationId,
            restaurantId: widget.restaurantId,
            branchId: widget.branchId,
            source: ImportSource(type: type, rawText: rawText),
            performedByStaffId: widget.performedByStaffId,
            performedAt: DateTime.now(),
          );

      if (type.supportsDeterministicLocalParsing) {
        final rawMenu = await ref.read(parseImportSourceProvider).call(
              importJobId: job.id,
              performedByStaffId: widget.performedByStaffId,
              performedAt: DateTime.now(),
            );
        final analyzed = const NormalizeAndAnalyzeParsedMenu()(rawMenu);
        await ref.read(createImportDraftProvider).call(
              importJobId: job.id,
              parsedMenu: analyzed,
              performedByStaffId: widget.performedByStaffId,
              performedAt: DateTime.now(),
            );
      } else {
        try {
          await ref.read(parseImportSourceProvider).call(
                importJobId: job.id,
                performedByStaffId: widget.performedByStaffId,
                performedAt: DateTime.now(),
              );
        } catch (_) {
          // Expected — parseFailed is the honest outcome for an
          // unsupported source; the job list still shows it.
        }
      }

      setState(() => _error = null);
      await _load();
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final jobs = _jobs;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Menü İçe Aktarma'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Yeni İçe Aktarma',
            onPressed: _startImport,
          ),
        ],
      ),
      body: SafeArea(
        child: jobs == null
            ? const LoadingView(message: 'İçe aktarma işleri yükleniyor...')
            : Column(
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Text(_error!,
                          style: AppTypography.bodySmall
                              .copyWith(color: AppColors.error)),
                    ),
                  Expanded(
                    child: jobs.isEmpty
                        ? const EmptyView(
                            icon: Icons.file_upload_outlined,
                            message: 'Henüz bir içe aktarma işi yok.',
                          )
                        : ListView(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            children: [
                              for (final job in jobs)
                                Padding(
                                  padding: const EdgeInsets.only(
                                      bottom: AppSpacing.sm),
                                  child: AppCard(
                                    padding: EdgeInsets.zero,
                                    child: ListTile(
                                      leading: Icon(
                                        job.status.name.contains('fail') ||
                                                job.status.name
                                                    .contains('reject')
                                            ? Icons.error_outline
                                            : job.status.name == 'committed'
                                                ? Icons.check_circle_outline
                                                : Icons.hourglass_top_outlined,
                                      ),
                                      title: Text(
                                          _sourceTypeLabels[job.source.type] ??
                                              job.source.type.name),
                                      subtitle: Text(
                                        '${job.status.name} · ${job.createdAt}',
                                      ),
                                      trailing: const Icon(Icons.chevron_right),
                                      onTap: () => Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => ImportReviewScreen(
                                            importJobId: job.id,
                                            performedByStaffId:
                                                widget.performedByStaffId,
                                          ),
                                        ),
                                      ),
                                    ),
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
