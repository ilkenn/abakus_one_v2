import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/models/customer_photo.dart';
import '../../../../shared/models/customer_photo_status.dart';
import '../../../../shared/widgets/feedback/empty_view.dart';
import '../../../../shared/widgets/feedback/error_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../../customer_photos/domain/customer_photo_client_rules.dart';
import '../../../customer_photos/presentation/providers/customer_photo_providers.dart';
import '../../../customer_photos/presentation/providers/customer_photo_upload_provider.dart';
import '../../../customer_photos/presentation/widgets/customer_photo_source_picker_sheet.dart';

/// Profile P.4.3A — the first FUNCTIONAL version of the customer's private
/// photo gallery. Deliberately not visually polished yet (locked
/// instruction: "functional correctness first") — real data, real upload,
/// real states, plain presentation.
class CustomerPhotoManagementScreen extends ConsumerWidget {
  const CustomerPhotoManagementScreen({super.key});

  Future<void> _showSourcePicker(BuildContext context, WidgetRef ref) async {
    final uploadState = ref.read(customerPhotoUploadProvider);
    if (uploadState.isBusy) {
      // Duplicate-tap guard, belt-and-suspenders with the disabled button.
      return;
    }

    final source = await showCustomerPhotoSourcePicker(context);
    if (source == null || !context.mounted) return;

    await ref.read(customerPhotoUploadProvider.notifier).pickAndUpload(
          source: source,
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final galleryAsync = ref.watch(customerPhotoGalleryProvider);
    final uploadState = ref.watch(customerPhotoUploadProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil Fotoğraflarım'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: SafeArea(
        child: galleryAsync.when(
          loading: () => const LoadingView(),
          error: (error, stackTrace) => ErrorView(
            message: 'Fotoğrafların yüklenemedi. Lütfen tekrar dene.',
            retryLabel: 'Tekrar Dene',
            onRetry: () => ref.invalidate(customerPhotoGalleryProvider),
          ),
          data: (photos) => _GalleryBody(
            photos: photos,
            uploadState: uploadState,
            onAddPhoto: () => _showSourcePicker(context, ref),
            onDismissError: () =>
                ref.read(customerPhotoUploadProvider.notifier).dismissError(),
          ),
        ),
      ),
    );
  }
}

class _GalleryBody extends StatelessWidget {
  const _GalleryBody({
    required this.photos,
    required this.uploadState,
    required this.onAddPhoto,
    required this.onDismissError,
  });

  final List<CustomerPhoto> photos;
  final CustomerPhotoUploadState uploadState;
  final VoidCallback onAddPhoto;
  final VoidCallback onDismissError;

  @override
  Widget build(BuildContext context) {
    final activeCount =
        photos.where((photo) => photo.countsTowardEligibleLimit).length;
    final limitReached = isCustomerPhotoQuotaFull(photos);
    final addDisabled = limitReached || uploadState.isBusy;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.xl,
            AppSpacing.md,
          ),
          child: Row(
            children: [
              Text(
                '$activeCount / ${CustomerPhoto.maxEligiblePhotos}',
                style: AppTypography.titleMedium.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                key: const Key('customerPhotoAddButton'),
                onPressed: addDisabled ? null : onAddPhoto,
                icon: uploadState.isBusy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('Fotoğraf Ekle'),
                style: ElevatedButton.styleFrom(
                  shape: const RoundedRectangleBorder(
                    borderRadius: AppRadius.kExtraLarge,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (limitReached) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'En fazla 10 profil fotoğrafı ekleyebilirsin.',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        if (uploadState.errorMessage != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: _UploadErrorBanner(
              message: uploadState.errorMessage!,
              onDismiss: onDismissError,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ] else if (uploadState.phase == CustomerPhotoUploadPhase.picking ||
            uploadState.phase == CustomerPhotoUploadPhase.uploading ||
            uploadState.phase == CustomerPhotoUploadPhase.requestingGrant) ...[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: _UploadStatusBanner(text: 'Fotoğraf yükleniyor...'),
          ),
          const SizedBox(height: AppSpacing.sm),
        ] else if (uploadState.phase ==
            CustomerPhotoUploadPhase.waitingForFinalize) ...[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: _UploadStatusBanner(
                text: 'Fotoğraf gönderildi, onay bekleniyor...'),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        Expanded(
          child: photos.isEmpty
              ? EmptyView(
                  icon: Icons.photo_camera_outlined,
                  message: 'Henüz bir profil fotoğrafı eklemedin.',
                  actionLabel: addDisabled ? null : 'Fotoğraf Ekle',
                  onAction: addDisabled ? null : onAddPhoto,
                )
              : GridView.builder(
                  key: const Key('customerPhotoGrid'),
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: AppSpacing.sm,
                    mainAxisSpacing: AppSpacing.sm,
                    childAspectRatio: 0.8,
                  ),
                  itemCount: photos.length,
                  itemBuilder: (context, index) =>
                      _CustomerPhotoTile(photo: photos[index]),
                ),
        ),
      ],
    );
  }
}

class _UploadErrorBanner extends StatelessWidget {
  const _UploadErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: AppRadius.kMedium,
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppColors.error, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: AppTypography.bodySmall.copyWith(color: AppColors.error),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: onDismiss,
            splashRadius: 18,
          ),
        ],
      ),
    );
  }
}

class _UploadStatusBanner extends StatelessWidget {
  const _UploadStatusBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: const BoxDecoration(
        color: AppColors.primaryExtraLight,
        borderRadius: AppRadius.kMedium,
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: AppTypography.bodySmall.copyWith(color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerPhotoTile extends ConsumerWidget {
  const _CustomerPhotoTile({required this.photo});

  final CustomerPhoto photo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytesAsync = ref.watch(customerPhotoBytesProvider(photo.photoRef));

    return ClipRRect(
      borderRadius: AppRadius.kMedium,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: AppColors.surfaceVariant),
          bytesAsync.when(
            loading: () => const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            error: (error, stackTrace) => const Center(
              child: Icon(Icons.broken_image_outlined,
                  color: AppColors.textSecondary),
            ),
            data: (bytes) => bytes == null
                ? const Center(
                    child: Icon(Icons.image_outlined,
                        color: AppColors.textSecondary),
                  )
                : Image.memory(bytes, fit: BoxFit.cover),
          ),
          Positioned(
            left: 4,
            right: 4,
            bottom: 4,
            child: _StatusChip(photo: photo),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.photo});

  final CustomerPhoto photo;

  Color get _color {
    switch (photo.status) {
      case CustomerPhotoStatus.approved:
        return AppColors.success;
      case CustomerPhotoStatus.rejected:
        return AppColors.error;
      case CustomerPhotoStatus.removed:
        return AppColors.textSecondary;
      case CustomerPhotoStatus.pendingReview:
      case CustomerPhotoStatus.underReview:
        return AppColors.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: _color,
        borderRadius: AppRadius.kSmall,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            customerPhotoStatusLabel(photo.status),
            style: AppTypography.caption.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          // Rejection reason: shown only because the owner-readable
          // customerPhotos Firestore document already exposes this field
          // to its own owner today (firestore.rules) — never reviewer
          // identity, audit, or grant data, which never appear here.
          if (photo.status == CustomerPhotoStatus.rejected &&
              (photo.rejectionReason?.isNotEmpty ?? false))
            Text(
              photo.rejectionReason!,
              style: AppTypography.caption.copyWith(color: Colors.white),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }
}
