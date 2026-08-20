import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/models/customer_photo_status.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../auth/presentation/screens/login_screen.dart';
import '../../../customer_photos/domain/customer_photo_client_rules.dart';
import '../../../customer_photos/presentation/providers/customer_photo_providers.dart';
import '../../domain/models/customer_identity.dart';
import '../providers/customer_identity_provider.dart';
import '../providers/profile_provider.dart';

/// P.4.3B (2026-08-20) — the top identity section of Profile, redesigned
/// to show the customer's REAL canonical identity
/// (`customers/{uid}`, via [customerIdentityProvider]) instead of the
/// phone number that used to be the primary hero line. Guest state
/// ([_GuestHero]) and the guest/authenticated switch itself are
/// deliberately UNCHANGED — still driven by [profileProvider] purely as
/// the "is a real session present" gate, exactly as before this task.
///
/// Owner photo priority (never applies to any other viewer — see
/// `resolveCustomerHeroPhoto`'s own doc comment for the full contract):
/// 1. The newest active `pendingReview`/`underReview` photo — private to
///    the owner, with a small "Onay Bekliyor"/"İnceleniyor" badge.
/// 2. Otherwise the canonical `approved` + PUBLICLY-selected photo (read
///    via `customerSelectedProfilePhotoRefProvider` —
///    `customerPublicProfiles`, never `CustomerPhoto.isSelectedAsProfilePhoto`
///    read in isolation).
/// 3. Otherwise an initials avatar built from [CustomerIdentity.initials].
///
/// Photo bytes are loaded ONLY for the single resolved photo
/// (`customerPhotoBytesProvider(photoRef)`) — the private gallery is
/// never eagerly downloaded in full.
class ProfileHeroCard extends ConsumerWidget {
  const ProfileHeroCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);

    return AppCard(
      key: const Key('profileHeroCard'),
      borderRadius: AppRadius.kLarge,
      boxShadow: AppShadows.card,
      padding: profile == null
          ? EdgeInsets.zero
          : const EdgeInsets.all(AppSpacing.xl),
      child: profile == null
          ? _GuestHero(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
              ),
            )
          : const Center(child: _AuthenticatedHero()),
    );
  }
}

class _AuthenticatedHero extends ConsumerWidget {
  const _AuthenticatedHero();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identityAsync = ref.watch(customerIdentityProvider);

    return identityAsync.when(
      loading: () => const _HeroSkeleton(),
      error: (error, stackTrace) => const _HeroUnavailable(),
      data: (identity) => identity == null
          ? const _HeroUnavailable()
          : _IdentityHero(identity: identity),
    );
  }
}

class _IdentityHero extends ConsumerWidget {
  const _IdentityHero({required this.identity});

  final CustomerIdentity identity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final galleryAsync = ref.watch(customerPhotoGalleryProvider);
    final selectedRefAsync = ref.watch(customerSelectedProfilePhotoRefProvider);
    final resolvedPhoto = resolveCustomerHeroPhoto(
      galleryPhotos: galleryAsync.valueOrNull ?? const [],
      selectedProfilePhotoRef: selectedRefAsync.valueOrNull,
    );

    Uint8List? photoBytes;
    if (resolvedPhoto != null) {
      photoBytes = ref
          .watch(customerPhotoBytesProvider(resolvedPhoto.photo.photoRef))
          .valueOrNull;
    }

    final isOwnerPrivatePresentation = resolvedPhoto != null &&
        resolvedPhoto.presentation !=
            CustomerHeroPhotoPresentation.approvedSelected;

    final workplaceOrSchool = switch (identity.occupationStatus) {
      CustomerOccupationStatus.working => identity.workplaceName,
      CustomerOccupationStatus.student => identity.educationalInstitutionName,
      CustomerOccupationStatus.other ||
      CustomerOccupationStatus.unknown =>
        null,
    };
    final hasWorkplaceOrSchool =
        workplaceOrSchool != null && workplaceOrSchool.isNotEmpty;
    final hasEmail = identity.email.isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _HeroAvatar(bytes: photoBytes, initials: identity.initials),
        if (isOwnerPrivatePresentation) ...[
          const SizedBox(height: AppSpacing.sm),
          _PendingStatusBadge(presentation: resolvedPhoto.presentation),
        ],
        const SizedBox(height: AppSpacing.md),
        Text(
          identity.fullName,
          key: const Key('profileHeroFullName'),
          textAlign: TextAlign.center,
          style: AppTypography.headlineMedium.copyWith(
            fontWeight: FontWeight.bold,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (hasEmail) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            identity.email,
            key: const Key('profileHeroEmail'),
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        if (hasWorkplaceOrSchool) ...[
          const SizedBox(height: 2),
          Text(
            workplaceOrSchool,
            key: const Key('profileHeroWorkplaceOrSchool'),
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}

class _HeroAvatar extends StatelessWidget {
  const _HeroAvatar({required this.bytes, required this.initials});

  final Uint8List? bytes;
  final String initials;

  static const double _diameter = 96;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _diameter,
      height: _diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.primaryLight, width: 3),
        boxShadow: AppShadows.subtle,
      ),
      child: ClipOval(
        child: bytes != null
            ? Image.memory(
                bytes!,
                key: const Key('profileHeroPhotoImage'),
                width: _diameter,
                height: _diameter,
                fit: BoxFit.cover,
              )
            : Container(
                key: const Key('profileHeroInitialsAvatar'),
                color: AppColors.primaryExtraLight,
                alignment: Alignment.center,
                child: initials.isNotEmpty
                    ? Text(
                        initials,
                        style: AppTypography.headlineMedium.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    : const Icon(
                        Icons.person_rounded,
                        size: 40,
                        color: AppColors.primary,
                      ),
              ),
      ),
    );
  }
}

class _PendingStatusBadge extends StatelessWidget {
  const _PendingStatusBadge({required this.presentation});

  final CustomerHeroPhotoPresentation presentation;

  @override
  Widget build(BuildContext context) {
    final status =
        presentation == CustomerHeroPhotoPresentation.pendingOwnerPrivate
            ? CustomerPhotoStatus.pendingReview
            : CustomerPhotoStatus.underReview;
    return Container(
      key: const Key('profileHeroPendingBadge'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: AppRadius.kPill,
      ),
      child: Text(
        customerPhotoStatusLabel(status),
        style: AppTypography.labelMedium.copyWith(
          color: AppColors.warning,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// A stable, premium placeholder shown only while [customerIdentityProvider]
/// is still resolving its first value — never a flash of fabricated
/// name/email.
class _HeroSkeleton extends StatelessWidget {
  const _HeroSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      key: Key('profileHeroSkeleton'),
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.surfaceVariant,
          ),
          child: SizedBox(width: 96, height: 96),
        ),
        SizedBox(height: AppSpacing.md),
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: AppRadius.kSmall,
          ),
          child: SizedBox(width: 160, height: 20),
        ),
        SizedBox(height: AppSpacing.sm),
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: AppRadius.kSmall,
          ),
          child: SizedBox(width: 120, height: 14),
        ),
      ],
    );
  }
}

/// Shown when the canonical identity document errored or genuinely
/// doesn't exist yet — deliberately NEVER a fabricated name/email, per
/// the locked "customer document temporarily unavailable" requirement.
class _HeroUnavailable extends StatelessWidget {
  const _HeroUnavailable();

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('profileHeroUnavailable'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.primaryExtraLight,
            border: Border.all(color: AppColors.primaryLight, width: 3),
          ),
          child: const Icon(
            Icons.person_rounded,
            size: 40,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Bilgiler şu anda görüntülenemiyor.',
          key: const Key('profileHeroUnavailableText'),
          textAlign: TextAlign.center,
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _GuestHero extends StatelessWidget {
  final VoidCallback onTap;

  const _GuestHero({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Hesabına giriş yap',
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.kLarge,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              const CircleAvatar(
                radius: 32,
                backgroundColor: AppColors.primaryExtraLight,
                child: Icon(
                  Icons.person_outline_rounded,
                  size: 32,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Hesabına Giriş Yap',
                      style: AppTypography.titleLarge.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Siparişlerini, Boncuklarını ve daha fazlasını '
                      'görmek için giriş yap.',
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
