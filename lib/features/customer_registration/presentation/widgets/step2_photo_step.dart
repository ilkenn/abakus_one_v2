import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/models/customer_photo.dart';
import '../../../../shared/models/customer_photo_status.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../customer_photos/data/customer_photo_picker.dart';
import '../../../customer_photos/domain/customer_photo_client_rules.dart';
import '../../../customer_photos/presentation/providers/customer_photo_providers.dart';
import '../../../customer_photos/presentation/providers/customer_photo_upload_provider.dart';
import '../../../customer_photos/presentation/widgets/customer_photo_source_picker_sheet.dart';

/// CR.1.2 — Step 2 ("Profil Fotoğrafın") of the two-step "Profilini
/// Tamamla" onboarding flow. **Fully optional** — [onFinished] is reached
/// via "Şimdilik Geç", a successful upload's own "Devam Et", or a failed
/// upload's "Daha Sonra Ekle"; none of these paths ever fail registration
/// itself, which Step 1 already committed server-side.
///
/// Reuses `customerPhotoUploadProvider`/`customerPhotoPickerProvider`
/// (the exact same state machine and picker `CustomerPhotoManagementScreen`
/// uses for the ordinary "Profil Fotoğraflarım" flow) rather than a second
/// implementation — the only addition is `purpose: 'profileOnboarding'`
/// on the upload call and this screen's own local preview-bytes state
/// (the provider itself never stores picked bytes).
///
/// **Physical-device fix (2026-08-20)**: [CustomerPhotoUploadPhase] is a
/// TRANSIENT signal only — the notifier itself resets back to `idle` the
/// instant `customerPhotoGalleryProvider` observes the finalized
/// `CustomerPhoto` (see that notifier's own `build()`). Once that has
/// happened, `uploadState.phase` can no longer distinguish "nothing was
/// ever uploaded" from "the upload finished" — both read as `idle`. This
/// widget therefore tracks the attempt's own grant/photo id
/// ([_attemptPhotoId], deterministically `photoId == grantId` per
/// `finalizeCustomerPhotoUpload`'s own invariant) and, once a matching
/// record appears in `customerPhotoGalleryProvider`, treats THAT
/// persisted [CustomerPhoto] — never the transient phase — as the
/// authoritative source of truth for what Step 2 renders.
class Step2PhotoStep extends ConsumerStatefulWidget {
  const Step2PhotoStep({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  ConsumerState<Step2PhotoStep> createState() => _Step2PhotoStepState();
}

class _Step2PhotoStepState extends ConsumerState<Step2PhotoStep> {
  // Local-only — the picked bytes never need to leave this widget. Kept
  // as the full [PickedCustomerPhoto] (not just the bytes) so "Tekrar
  // Dene" can retry the exact same picked image without prompting the
  // picker a second time.
  PickedCustomerPhoto? _picked;

  /// The current attempt's grant/photo id, captured the instant the
  /// upload notifier exposes it and retained even after the notifier
  /// resets back to `idle`. `null` means "no attempt has produced a
  /// grant yet" — never inferred from `CustomerPhotoUploadPhase` alone.
  String? _attemptPhotoId;

  Future<void> _pickAndUpload() async {
    final source = await showCustomerPhotoSourcePicker(context);
    if (source == null || !mounted) return;

    final picked =
        await ref.read(customerPhotoPickerProvider).pickImage(source: source);
    if (picked == null || !mounted) return; // cancelled — stay idle.

    setState(() {
      _picked = picked;
      // A fresh attempt supersedes any prior persisted record this
      // widget was showing (relevant after a rejection — see
      // `_retryAfterRejection`).
      _attemptPhotoId = null;
    });
    await ref.read(customerPhotoUploadProvider.notifier).uploadPicked(
          picked: picked,
          purpose: 'profileOnboarding',
        );
  }

  Future<void> _retry() async {
    final picked = _picked;
    if (picked == null) return;
    await ref.read(customerPhotoUploadProvider.notifier).uploadPicked(
          picked: picked,
          purpose: 'profileOnboarding',
        );
  }

  /// A persisted, moderator-rejected photo can never be usefully
  /// resubmitted as-is — "Tekrar Dene" here means picking a genuinely
  /// new photo, not replaying the already-reviewed-and-rejected bytes.
  Future<void> _retryAfterRejection() async {
    setState(() {
      _picked = null;
      _attemptPhotoId = null;
    });
    await _pickAndUpload();
  }

  /// The persisted `CustomerPhoto` this attempt produced, if the gallery
  /// has observed it — matched on the exact id (never "latest photo" or
  /// a timestamp heuristic), the declared onboarding purpose, and
  /// ownership, so an unrelated photo (different id, different intent,
  /// or — defense in depth — a different owner) can never be mistaken
  /// for this attempt's own result.
  CustomerPhoto? _findPersistedAttemptPhoto(
    List<CustomerPhoto> photos,
    String? currentUid,
  ) {
    final attemptId = _attemptPhotoId;
    if (attemptId == null) return null;
    for (final photo in photos) {
      if (photo.id == attemptId &&
          photo.purpose == 'profileOnboarding' &&
          photo.customerId == currentUid) {
        return photo;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    // `ref.listen` fires SYNCHRONOUSLY the instant the notifier sets
    // `pendingGrantId` — unlike `ref.watch`, whose rebuild can be
    // deferred past the moment the gallery stream observes the
    // finalized photo and the notifier resets back to `idle`. This is
    // what closes the physical-device race: the id is captured the
    // moment it exists, never read back out after the fact.
    ref.listen<CustomerPhotoUploadState>(customerPhotoUploadProvider,
        (previous, next) {
      if (next.pendingGrantId != null) {
        _attemptPhotoId = next.pendingGrantId;
      }
    });

    final uploadState = ref.watch(customerPhotoUploadProvider);
    final galleryAsync = ref.watch(customerPhotoGalleryProvider);
    final galleryPhotos = galleryAsync.valueOrNull ?? const <CustomerPhoto>[];
    final currentUid = ref.watch(authProvider).session?.uid;
    final quotaFull = isCustomerPhotoQuotaFull(galleryPhotos);
    final persistedPhoto =
        _findPersistedAttemptPhoto(galleryPhotos, currentUid);

    // Once a persisted record exists for this attempt, it is
    // authoritative — the transient phase is never consulted again for
    // it, closing the exact "loses the submitted-photo presentation"
    // defect this fix targets.
    final isUploadingNow = persistedPhoto == null &&
        (uploadState.phase == CustomerPhotoUploadPhase.picking ||
            uploadState.phase == CustomerPhotoUploadPhase.requestingGrant ||
            uploadState.phase == CustomerPhotoUploadPhase.uploading);
    final isWaitingForFinalize = persistedPhoto == null &&
        uploadState.phase == CustomerPhotoUploadPhase.waitingForFinalize;
    final isTransientFailed = persistedPhoto == null &&
        uploadState.phase == CustomerPhotoUploadPhase.failed;
    final isRejected = persistedPhoto?.status == CustomerPhotoStatus.rejected;

    // After persistence, the owner-authorized `customerPhotoBytesProvider`
    // (never `getDownloadURL`, never a public URL) is authoritative;
    // the local picked bytes remain only as a flash-free fallback while
    // that fetch is still in flight.
    Uint8List? previewBytes = _picked?.bytes;
    if (persistedPhoto != null) {
      final bytesAsync =
          ref.watch(customerPhotoBytesProvider(persistedPhoto.photoRef));
      previewBytes = bytesAsync.valueOrNull ?? previewBytes;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Profil Fotoğrafın',
            key: const Key('step2PhotoTitle'),
            style: AppTypography.titleLarge.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Seni daha kişisel bir Abaküs deneyimiyle karşılayalım. '
            'Fotoğrafın yayınlanmadan önce onaylanır.',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          AppCard(
            padding: const EdgeInsets.all(AppSpacing.xl),
            borderRadius: AppRadius.kExtraLarge,
            child: Column(
              children: [
                _PhotoPreview(bytes: previewBytes),
                if (persistedPhoto != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _StatusPill(
                    key: Key(
                      persistedPhoto.status == CustomerPhotoStatus.pendingReview
                          ? 'step2PhotoPendingReviewChip'
                          : 'step2PhotoPersistedStatusChip',
                    ),
                    label: customerPhotoStatusLabel(persistedPhoto.status),
                    color: _statusPillColor(persistedPhoto.status),
                  ),
                  if (persistedPhoto.status ==
                      CustomerPhotoStatus.pendingReview) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Fotoğrafını sen görebilirsin. Diğer kullanıcılar '
                      'yalnızca onaylandıktan sonra görebilir.',
                      key: const Key('step2PhotoPendingReviewExplanation'),
                      textAlign: TextAlign.center,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ] else if (isRejected &&
                      (persistedPhoto.rejectionReason?.isNotEmpty ??
                          false)) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      persistedPhoto.rejectionReason!,
                      key: const Key('step2PhotoRejectionReason'),
                      textAlign: TextAlign.center,
                      style: AppTypography.bodySmall
                          .copyWith(color: AppColors.error),
                    ),
                  ],
                ] else if (isWaitingForFinalize) ...[
                  const SizedBox(height: AppSpacing.lg),
                  const _StatusPill(
                    key: Key('step2PhotoPendingReviewChip'),
                    label: 'Onay Bekliyor',
                    color: AppColors.warning,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Fotoğrafını sen görebilirsin. Diğer kullanıcılar '
                    'yalnızca onaylandıktan sonra görebilir.',
                    key: const Key('step2PhotoPendingReviewExplanation'),
                    textAlign: TextAlign.center,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ] else if (isTransientFailed) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    uploadState.errorMessage ?? 'Fotoğraf yüklenemedi.',
                    key: const Key('step2PhotoErrorText'),
                    textAlign: TextAlign.center,
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.error),
                  ),
                ] else if (quotaFull) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'En fazla 10 profil fotoğrafı ekleyebilirsin.',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
          if (persistedPhoto != null && isRejected) ...[
            _PrimaryActionButton(
              key: const Key('step2PhotoRetryButton'),
              label: 'Tekrar Dene',
              onPressed: isUploadingNow ? null : _retryAfterRejection,
            ),
            const SizedBox(height: AppSpacing.md),
            _SecondaryActionButton(
              key: const Key('step2PhotoLaterButton'),
              label: 'Daha Sonra Ekle',
              onPressed: isUploadingNow ? null : widget.onFinished,
            ),
          ] else if (persistedPhoto != null || isWaitingForFinalize)
            _PrimaryActionButton(
              key: const Key('step2PhotoContinueButton'),
              label: 'Devam Et',
              onPressed: widget.onFinished,
            )
          else if (isTransientFailed) ...[
            _PrimaryActionButton(
              key: const Key('step2PhotoRetryButton'),
              label: 'Tekrar Dene',
              onPressed: isUploadingNow ? null : _retry,
            ),
            const SizedBox(height: AppSpacing.md),
            _SecondaryActionButton(
              key: const Key('step2PhotoLaterButton'),
              label: 'Daha Sonra Ekle',
              onPressed: widget.onFinished,
            ),
          ] else ...[
            _PrimaryActionButton(
              key: const Key('step2PhotoAddButton'),
              label: 'Fotoğraf Ekle',
              isLoading: isUploadingNow,
              onPressed: (quotaFull || isUploadingNow) ? null : _pickAndUpload,
            ),
            const SizedBox(height: AppSpacing.md),
            _SecondaryActionButton(
              key: const Key('step2PhotoSkipButton'),
              label: 'Şimdilik Geç',
              onPressed: isUploadingNow ? null : widget.onFinished,
            ),
          ],
        ],
      ),
    );
  }
}

/// Mirrors `CustomerPhotoManagementScreen`'s own `_StatusChip` color
/// convention (`AppColors.success`/`error`/`warning`) — never a new,
/// unrelated palette for the same statuses.
Color _statusPillColor(CustomerPhotoStatus status) {
  switch (status) {
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

class _PhotoPreview extends StatelessWidget {
  const _PhotoPreview({required this.bytes});

  final Uint8List? bytes;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: Container(
        width: 140,
        height: 140,
        color: AppColors.surfaceVariant,
        child: bytes != null
            ? Image.memory(
                bytes!,
                key: const Key('step2PhotoPreviewImage'),
                fit: BoxFit.cover,
              )
            : const Icon(
                Icons.person_outline_rounded,
                size: 64,
                color: AppColors.textSecondary,
              ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    super.key,
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadius.kPill,
      ),
      child: Text(
        label,
        style: AppTypography.labelMedium.copyWith(
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _PrimaryActionButton extends StatelessWidget {
  const _PrimaryActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadius.kExtraLarge,
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppColors.onPrimary,
                ),
              )
            : Text(
                label,
                style: AppTypography.bodyLarge.copyWith(
                  color: AppColors.onPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }
}

class _SecondaryActionButton extends StatelessWidget {
  const _SecondaryActionButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadius.kExtraLarge,
          ),
        ),
        child: Text(
          label,
          style: AppTypography.bodyLarge.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
