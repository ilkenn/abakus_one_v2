import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../auth/presentation/screens/login_screen.dart';
import '../../domain/models/profile_model.dart';
import '../providers/profile_provider.dart';

/// Compact premium account card — P.1 (2026-08-19) replacement for the old
/// oversized centered avatar/name/email block. Two states, both reading
/// [profileProvider] directly (no separate `authProvider` watch needed —
/// the provider itself is `null` exactly when signed out):
///
/// - Authenticated: real avatar area (photo if one exists, otherwise a
///   placeholder icon — no upload flow yet, see class doc below), the
///   real phone number as the primary identity line, and the real email
///   line only when [ProfileModel.email] is actually non-empty. Never a
///   fabricated name/email.
/// - Guest: a premium "Hesabına Giriş Yap" state — real CTA into
///   [LoginScreen], never a placeholder identity standing in for a person
///   who hasn't signed in.
///
/// Deliberately has **no edit affordance in either state** — the previous
/// screen's pencil badge only faked a successful photo update (a
/// hardcoded local path, no real picker/upload/storage). Per the locked
/// P.1 decision, a fake edit flow must not be carried into the new hero;
/// a real one returns once photo upload is actually built (see the P.4
/// profile-photo architecture audit).
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
          : const EdgeInsets.all(
              AppSpacing.lg,
            ),
      child: profile == null
          ? _GuestHero(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
              ),
            )
          : _AuthenticatedHero(profile: profile),
    );
  }
}

class _AuthenticatedHero extends StatelessWidget {
  final ProfileModel profile;

  const _AuthenticatedHero({required this.profile});

  @override
  Widget build(BuildContext context) {
    final hasCustomImage = profile.profilePicturePath != null && !kIsWeb;
    final hasEmail = profile.email.isNotEmpty;

    return Row(
      children: [
        CircleAvatar(
          radius: 32,
          backgroundColor: AppColors.primaryExtraLight,
          backgroundImage: hasCustomImage
              ? FileImage(File(profile.profilePicturePath!))
              : null,
          child: !hasCustomImage
              ? const Icon(
                  Icons.person_rounded,
                  size: 32,
                  color: AppColors.primary,
                )
              : null,
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                profile.name,
                style: AppTypography.titleLarge.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (hasEmail) ...[
                const SizedBox(height: 2),
                Text(
                  profile.email,
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
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
