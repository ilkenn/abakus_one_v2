import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../domain/audit/audit_center_entry.dart';
import '../providers/admin_dependencies_provider.dart';

const _domainLabels = {
  'courier': 'Kurye',
  'kitchen': 'Mutfak',
  'restaurant-operations': 'Restoran Operasyonları',
  'admin': 'Yönetici',
};

/// Unified, read-only Audit Center — Phase 6M (`docs/decisions.md`
/// ADR-023). A **projection**, not a merged write-side store: every
/// underlying audit trail keeps writing to its own repository exactly as
/// before, this screen only reads a normalized view across 4 of them via
/// [BuildAuditCenterProjection]. Cash, closure, courier-settlement, and
/// CRM audit trails are not included here — see that use case's doc
/// comment for why — and remain viewable only within their own existing
/// screens.
///
/// Filtering (actor, domain) is entirely client-side, applied after
/// fetching each source's full branch-scoped history — "future backend
/// query seam," not real server-side filtering.
class AuditCenterScreen extends ConsumerStatefulWidget {
  const AuditCenterScreen({super.key, required this.branchId});

  final String branchId;

  @override
  ConsumerState<AuditCenterScreen> createState() => _AuditCenterScreenState();
}

class _AuditCenterScreenState extends ConsumerState<AuditCenterScreen> {
  List<AuditCenterEntry>? _entries;
  String? _domainFilter;
  final _actorController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _actorController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final entries = await ref.read(buildAuditCenterProjectionProvider).call(
          branchId: widget.branchId,
          actorId: _actorController.text.trim().isEmpty
              ? null
              : _actorController.text.trim(),
          domain: _domainFilter,
        );
    if (!mounted) return;
    setState(() => _entries = entries);
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Denetim Merkezi'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _actorController,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.person_search_outlined),
                        hintText: 'Aktör kimliğine göre filtrele',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _load(),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  DropdownButton<String?>(
                    value: _domainFilter,
                    hint: const Text('Tüm alanlar'),
                    items: [
                      const DropdownMenuItem(
                          value: null, child: Text('Tüm alanlar')),
                      for (final entry in _domainLabels.entries)
                        DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                    ],
                    onChanged: (value) {
                      setState(() => _domainFilter = value);
                      _load();
                    },
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  IconButton(
                    icon: const Icon(Icons.filter_alt_outlined),
                    tooltip: 'Filtrele',
                    onPressed: _load,
                  ),
                ],
              ),
            ),
            Expanded(
              child: entries == null
                  ? const LoadingView(
                      message: 'Denetim kayıtları yükleniyor...')
                  : entries.isEmpty
                      ? const EmptyView(
                          icon: Icons.fact_check_outlined,
                          message: 'Bu filtrelerle eşleşen denetim kaydı yok.',
                        )
                      : ListView(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.lg),
                          children: [
                            for (final entry in entries)
                              Padding(
                                padding: const EdgeInsets.only(
                                    bottom: AppSpacing.sm),
                                child: AppCard(
                                  padding: const EdgeInsets.all(AppSpacing.md),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          _DomainBadge(domain: entry.domain),
                                          const SizedBox(width: AppSpacing.sm),
                                          Expanded(
                                            child: Text(
                                              entry.description,
                                              style: AppTypography.bodyMedium,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: AppSpacing.xs),
                                      Text(
                                        'Aktör: ${entry.actorId}'
                                        '${entry.actorRole != null ? ' (${entry.actorRole})' : ''} · '
                                        'Hedef: ${entry.targetEntityId} · '
                                        '${entry.timestamp}',
                                        style: AppTypography.bodySmall.copyWith(
                                            color: AppColors.textSecondary),
                                      ),
                                    ],
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

class _DomainBadge extends StatelessWidget {
  const _DomainBadge({required this.domain});

  final String domain;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        _domainLabels[domain] ?? domain,
        style: AppTypography.labelMedium.copyWith(color: AppColors.primary),
      ),
    );
  }
}
