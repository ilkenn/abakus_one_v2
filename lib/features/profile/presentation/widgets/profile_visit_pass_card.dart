import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../crm/domain/segmentation/customer.dart';
import '../../../crm/presentation/providers/current_customer_provider.dart';
import '../../../crm/presentation/screens/customer_visit_passport_screen.dart';
import '../../../navigation/presentation/providers/current_branch_provider.dart';

/// Compact premium "Ziyaret Pasosu" card — P.3 (2026-08-19), moved out of
/// the old flat settings list into its own card. Visit Pass and Boncuk are
/// two deliberately separate reward programs (ADR-021/ADR-022 — points vs.
/// visit-count thresholds); this card's own copy states that distinction
/// rather than letting a shared "premium card" template make the two look
/// like the same thing.
///
/// Reads/navigates using real [currentCustomerProvider] data and the real
/// [CustomerVisitPassportScreen] — no visit count or reward is fabricated
/// here (there's nothing to fabricate; this card shows no numbers at all,
/// only a static description and a QR-inspired icon).
///
/// P.3.1 (2026-08-19): the caller is solely responsible for only mounting
/// this widget for an authenticated customer — a guest has no
/// [currentCustomerProvider] to resolve at all, so Visit Pass has nothing
/// to show them (see `ProfileScreen`'s `isAuthenticated` gate). On tap,
/// [_handleTap] awaits `currentCustomerProvider.future` instead of reading
/// its possibly-still-loading cached value — the old synchronous
/// `ref.read(...).valueOrNull` could race the provider's first-ever
/// evaluation (nothing else in this screen watches it ahead of time) and
/// silently do nothing on a first tap. A resolution failure/null result
/// now surfaces a real, non-technical message instead of that silent
/// no-op; `_isResolving` blocks a second concurrent tap rather than
/// letting a double-tap fire two navigations or two error messages.
class ProfileVisitPassCard extends ConsumerStatefulWidget {
  const ProfileVisitPassCard({super.key});

  @override
  ConsumerState<ProfileVisitPassCard> createState() =>
      _ProfileVisitPassCardState();
}

class _ProfileVisitPassCardState extends ConsumerState<ProfileVisitPassCard> {
  bool _isResolving = false;

  Future<void> _handleTap() async {
    if (_isResolving) return;
    setState(() => _isResolving = true);

    Customer? customer;
    try {
      // Awaits resolution instead of reading whatever's cached right now
      // — `currentCustomerProvider` is never `watch`ed ahead of time
      // anywhere in this screen, so a bare `ref.read(...)` here could
      // still be `AsyncLoading` on the very first tap.
      customer = await ref.read(currentCustomerProvider.future);
    } catch (_) {
      customer = null;
    }

    if (!mounted) return;
    setState(() => _isResolving = false);

    if (customer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ziyaret pasosuna şu anda ulaşılamıyor. Lütfen tekrar dene.',
          ),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CustomerVisitPassportScreen(
          customerId: customer!.id,
          branchId: ref.read(currentBranchIdProvider),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Ziyaret Pasosu, ziyaret sayına özel ayrı ödül programı',
      child: AppCard(
        key: const Key('profileVisitPassCard'),
        borderRadius: AppRadius.kLarge,
        boxShadow: AppShadows.card,
        padding: EdgeInsets.zero,
        child: InkWell(
          borderRadius: AppRadius.kLarge,
          onTap: _handleTap,
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
                        Icons.qr_code_2_rounded,
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
                          'Ziyaret Pasosu',
                          style: AppTypography.bodyLarge.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Ziyaret sayına özel ayrı ödül programı',
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.textSecondary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (_isResolving)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
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
