import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../application/use_cases/moderate_customer_photo.dart';
import '../../domain/customer/customer_photo.dart';
import '../providers/admin_dependencies_provider.dart';

/// Customer photo moderation queue — Phase 6G (`docs/decisions.md`
/// ADR-023). Lists every photo currently `pendingReview`/`underReview`.
/// No automatic AI moderation — "do not implement automatic AI
/// moderation unless an approved service exists" (none does). Each
/// photo shows its opaque [CustomerPhoto.photoRef] as a reference label,
/// never a rendered image — no real media storage exists to fetch
/// bytes from.
class CustomerPhotoModerationScreen extends ConsumerStatefulWidget {
  const CustomerPhotoModerationScreen({
    super.key,
    this.authorizationPolicy,
    this.performedByStaffId = '',
  });

  final PosAuthorizationPolicy? authorizationPolicy;
  final String performedByStaffId;

  @override
  ConsumerState<CustomerPhotoModerationScreen> createState() =>
      _CustomerPhotoModerationScreenState();
}

class _CustomerPhotoModerationScreenState
    extends ConsumerState<CustomerPhotoModerationScreen> {
  List<CustomerPhoto>? _photos;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final photos =
        await ref.read(customerPhotoRepositoryProvider).findPendingReview();
    if (!mounted) return;
    setState(() => _photos = photos);
  }

  Future<void> _moderate(
    CustomerPhoto photo,
    CustomerPhotoModerationAction action, {
    String? rejectionReason,
  }) async {
    final policy = widget.authorizationPolicy;
    if (policy == null) {
      setState(() => _error = 'Yetki politikası tanımlı değil.');
      return;
    }
    try {
      await ModerateCustomerPhoto(
        authorizationPolicy: policy,
        repository: ref.read(customerPhotoRepositoryProvider),
        auditRepository: ref.read(adminAuditEntryRepositoryProvider),
      )(
        photoId: photo.id,
        moderationAction: action,
        rejectionReason: rejectionReason,
        performedByStaffId: widget.performedByStaffId,
        performedAt: DateTime.now(),
      );
      setState(() => _error = null);
      await _load();
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _reject(CustomerPhoto photo) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reddetme Nedeni'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Reddet'),
          ),
        ],
      ),
    );
    if (reason == null) return;
    await _moderate(photo, CustomerPhotoModerationAction.reject,
        rejectionReason: reason);
  }

  @override
  Widget build(BuildContext context) {
    final photos = _photos;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Fotoğraf Denetimi'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: photos == null
            ? const LoadingView(message: 'Kuyruk yükleniyor...')
            : photos.isEmpty
                ? const EmptyView(
                    icon: Icons.image_search_outlined,
                    message: 'İncelenecek fotoğraf yok.',
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
                      for (final photo in photos)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: AppCard(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.image_outlined,
                                        color: AppColors.textSecondary),
                                    const SizedBox(width: AppSpacing.sm),
                                    Expanded(
                                      child: Text(
                                        'Müşteri: ${photo.customerId}\n'
                                        'Referans: ${photo.photoRef}\n'
                                        'Yüklendi: ${photo.uploadedAt}',
                                        style: AppTypography.bodySmall,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                Wrap(
                                  spacing: AppSpacing.sm,
                                  children: [
                                    ElevatedButton(
                                      onPressed: () => _moderate(
                                          photo,
                                          CustomerPhotoModerationAction
                                              .approve),
                                      child: const Text('Onayla'),
                                    ),
                                    OutlinedButton(
                                      onPressed: () => _reject(photo),
                                      child: const Text('Reddet'),
                                    ),
                                    OutlinedButton(
                                      onPressed: () => _moderate(photo,
                                          CustomerPhotoModerationAction.remove),
                                      child: const Text('Kaldır'),
                                    ),
                                    OutlinedButton(
                                      onPressed: () => _moderate(
                                          photo,
                                          CustomerPhotoModerationAction
                                              .returnToReview),
                                      child: const Text('İncelemeye Al'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
      ),
    );
  }
}
