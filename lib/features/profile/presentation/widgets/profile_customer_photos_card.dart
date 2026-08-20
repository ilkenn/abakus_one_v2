import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/models/customer_photo.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../customer_photos/presentation/providers/customer_photo_providers.dart';
import '../screens/customer_photo_management_screen.dart';

/// Profile P.4.3A — "Profil Fotoğraflarım" entry point. Caller is solely
/// responsible for only mounting this for an authenticated customer (see
/// `ProfileScreen`'s `isAuthenticated` gate) — a guest must never see it.
/// Unlike `ProfileVisitPassCard`, no async identity resolution is needed
/// on tap: `authProvider`'s session uid is already the real Firebase Auth
/// uid, synchronously available the moment this card is even eligible to
/// be shown.
class ProfileCustomerPhotosCard extends ConsumerWidget {
  const ProfileCustomerPhotosCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final galleryAsync = ref.watch(customerPhotoGalleryProvider);
    // `.valueOrNull` — never the unsafe `.value`, which rethrows the
    // underlying error when the gallery stream is in an `AsyncError`
    // state with no cached previous value (e.g. Firebase genuinely
    // unavailable) — this card must degrade to its "no count yet"
    // fallback subtitle instead of crashing the whole screen.
    final activeCount = galleryAsync.valueOrNull
        ?.where((photo) => photo.countsTowardEligibleLimit)
        .length;

    return Semantics(
      button: true,
      label: 'Profil Fotoğraflarım, profil fotoğraflarını yönet',
      child: AppCard(
        key: const Key('profileCustomerPhotosCard'),
        borderRadius: AppRadius.kLarge,
        boxShadow: AppShadows.card,
        padding: EdgeInsets.zero,
        child: InkWell(
          borderRadius: AppRadius.kLarge,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const CustomerPhotoManagementScreen(),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ExcludeSemantics(
              child: Row(
                children: [
                  const SizedBox(
                    width: 48,
                    height: 48,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.primaryExtraLight,
                        borderRadius: AppRadius.kMedium,
                      ),
                      child: Icon(
                        Icons.photo_camera_outlined,
                        color: AppColors.primary,
                        size: 26,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Profil Fotoğraflarım',
                          style: AppTypography.bodyLarge.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          activeCount == null
                              ? 'Fotoğraflarını yönet'
                              : '$activeCount / ${CustomerPhoto.maxEligiblePhotos} fotoğraf',
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
