import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/real_customer_check.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/feedback/error_view.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../auth/presentation/screens/login_screen.dart';
import '../../data/reservation_gateway.dart';
import '../../domain/models/reservation_draft.dart';
import '../../domain/reservation_error_messages.dart';
import '../providers/preorder_cart_provider.dart';
import '../providers/reservation_branch_info_provider.dart';
import '../providers/reservation_dependencies_provider.dart';
import '../providers/reservation_draft_provider.dart';
import '../widgets/area_step.dart';
import '../widgets/date_step.dart';
import '../widgets/party_size_step.dart';
import '../widgets/preorder_step.dart';
import '../widgets/reservation_step_scaffold.dart';
import '../widgets/reservation_summary_bar.dart';
import '../widgets/review_step.dart';
import '../widgets/time_step.dart';

const int _stepCount = 6;

/// The customer reservation flow's entry point — Faz R.2. Real-phone-auth
/// gated in-place (mirrors `TakeawayBranchSelectionScreen`'s exact
/// pattern: an icon + copy + "Giriş Yap" button shown within this same
/// screen, not a redirect), a progressive/guided 6-step experience over a
/// single [ReservationDraft] (Faz R.2 §24 — never step-local state).
class ReservationFlowScreen extends ConsumerStatefulWidget {
  const ReservationFlowScreen({super.key});

  @override
  ConsumerState<ReservationFlowScreen> createState() =>
      _ReservationFlowScreenState();
}

class _ReservationFlowScreenState extends ConsumerState<ReservationFlowScreen> {
  int _stepIndex = 0;
  bool _isSubmitting = false;
  bool _submitSucceeded = false;
  String? _submitError;
  late final String _submissionKey;
  late final TextEditingController _firstNameController;
  late final TextEditingController _lastNameController;

  @override
  void initState() {
    super.initState();
    // Generated once, reused on every retry within this screen's lifetime
    // — mirrors `TakeawayCheckoutScreen`'s own established idempotency-key
    // pattern exactly, so a network retry never creates a duplicate
    // reservation/preorder (the backend derives
    // `sha256(actorUid|submissionKey)` server-side).
    _submissionKey =
        '${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(this)}';
    final draft = ref.read(reservationDraftProvider);
    _firstNameController = TextEditingController(text: draft.contactFirstName);
    _lastNameController = TextEditingController(text: draft.contactLastName);
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  void _goToStep(int index) {
    setState(() => _stepIndex = index.clamp(0, _stepCount - 1));
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    final draft = ref.read(reservationDraftProvider);
    final preorderItems = ref.read(preorderCartProvider);
    final gateway = ref.read(reservationGatewayProvider);

    try {
      final result = await gateway.submitReservation(
        submissionKey: _submissionKey,
        restaurantId: reservationRestaurantId,
        branchId: reservationBranchId,
        areaId: draft.area!.id,
        partySize: draft.partySize!,
        requestedTime: draft.time!,
        contactFirstName: draft.contactFirstName.trim(),
        contactLastName: draft.contactLastName.trim(),
        preorderItems: preorderItems.isEmpty
            ? null
            : [
                for (final item in preorderItems)
                  ReservationPreorderProductItem(
                    productId: item.id,
                    quantity: item.quantity,
                    selectedModifiers: [
                      for (final modifier in item.selectedModifiers)
                        (
                          groupId: modifier.groupId,
                          optionId: modifier.optionId
                        ),
                    ],
                  ),
              ],
      );

      if (!mounted) return;
      // `context.go` kicks off go_router's own (internally async)
      // route-matching pipeline rather than swapping the tree
      // synchronously, so this widget can still rebuild before the
      // navigation actually unmounts it. Resetting the draft/cart right
      // here would let that in-between rebuild hit `ReviewStep`, which
      // reads `draft.time!` unconditionally and would crash on the null.
      // `_submitSucceeded` short-circuits `build()` below before it ever
      // reaches step content again, so the reset is safe to do immediately
      // — nothing left in this widget's own tree still depends on the
      // draft once this flips.
      setState(() => _submitSucceeded = true);
      ref.read(reservationDraftProvider.notifier).reset();
      ref.read(preorderCartProvider.notifier).clearCart();
      context.go(AppRoutes.reservationConfirmation(result.reservationId));
    } on ReservationException catch (error) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _submitError = reservationErrorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    if (!isRealCustomer(authState)) {
      return const _LoginRequiredScreen(
          currentLocation: AppRoutes.reservationPrefix);
    }
    if (_submitSucceeded) {
      // Submission already went through and `context.go` is on its way to
      // the confirmation route — nothing here reads the (now reset) draft
      // again while that navigation lands.
      return const Scaffold(
        body:
            Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    final branchInfoAsync = ref.watch(reservationBranchInfoProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rezervasyon'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            if (_stepIndex > 0) {
              _goToStep(_stepIndex - 1);
            } else {
              Navigator.maybePop(context);
            }
          },
        ),
      ),
      body: SafeArea(
        child: branchInfoAsync.when(
          loading: () =>
              const LoadingView(message: 'Rezervasyon bilgileri yükleniyor...'),
          error: (error, stackTrace) => ErrorView(
            message: error is ReservationException
                ? reservationErrorMessage(error)
                : 'Rezervasyon bilgileri yüklenirken bir sorun oluştu.',
            retryLabel: 'Tekrar Dene',
            onRetry: () => ref.invalidate(reservationBranchInfoProvider),
          ),
          data: (branchInfo) {
            final draft = ref.watch(reservationDraftProvider);
            final notifier = ref.read(reservationDraftProvider.notifier);
            // A sensible default so step 1 always has a valid selection —
            // client-side UX convenience only.
            if (draft.partySize == null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                notifier.setPartySize(1);
              });
            }
            final effectivePartySize = draft.partySize ?? 1;

            return Column(
              children: [
                const ReservationSummaryBar(),
                Expanded(
                  child: _buildStep(
                    context: context,
                    draft: draft,
                    notifier: notifier,
                    branchInfo: branchInfo,
                    effectivePartySize: effectivePartySize,
                    authState: authState,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildStep({
    required BuildContext context,
    required ReservationDraft draft,
    required ReservationDraftNotifier notifier,
    required dynamic branchInfo,
    required int effectivePartySize,
    required AuthState authState,
  }) {
    switch (_stepIndex) {
      case 0:
        return ReservationStepScaffold(
          title: 'Kaç Kişilik?',
          subtitle: 'Rezervasyon için kişi sayısını seçin.',
          body: PartySizeStep(
            value: effectivePartySize,
            maxPartySize: branchInfo.policy.maxPartySize as int,
            onChanged: notifier.setPartySize,
          ),
          onPrimary: () => _goToStep(1),
        );
      case 1:
        return ReservationStepScaffold(
          title: 'Hangi Alan?',
          subtitle: 'Rezervasyon için bir alan seçin.',
          body: AreaStep(
            areas: branchInfo.areas,
            selectedAreaId: draft.area?.id,
            onSelected: notifier.setArea,
          ),
          onPrimary: draft.area != null ? () => _goToStep(2) : null,
          secondaryLabel: 'Geri',
          onSecondary: () => _goToStep(0),
        );
      case 2:
        final now = DateTime.now();
        return ReservationStepScaffold(
          title: 'Hangi Tarih?',
          subtitle: 'Uygun bir tarih seçin.',
          body: DateStep(
            selectedDate: draft.date,
            firstSelectableDate: DateTime(now.year, now.month, now.day),
            lastSelectableDate: DateTime(now.year, now.month, now.day).add(
                Duration(days: branchInfo.policy.bookingHorizonDays as int)),
            onDateSelected: notifier.setDate,
          ),
          onPrimary: draft.date != null ? () => _goToStep(3) : null,
          secondaryLabel: 'Geri',
          onSecondary: () => _goToStep(1),
        );
      case 3:
        final date = draft.date!;
        final dateKey =
            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        return ReservationStepScaffold(
          title: 'Hangi Saat?',
          subtitle: 'Uygun bir saat seçin.',
          body: TimeStep(
            availabilityKey: (
              areaId: draft.area!.id,
              dateKey: dateKey,
              partySize: effectivePartySize,
            ),
            selectedTime: draft.time,
            onTimeSelected: notifier.setTime,
          ),
          onPrimary: draft.time != null ? () => _goToStep(4) : null,
          secondaryLabel: 'Geri',
          onSecondary: () => _goToStep(2),
        );
      case 4:
        final preorderItems = ref.watch(preorderCartProvider);
        return ReservationStepScaffold(
          title: 'Ön Sipariş',
          subtitle: 'İsterseniz masanız için şimdiden sipariş verebilirsiniz.',
          body: const PreorderStep(),
          primaryLabel: preorderItems.isEmpty ? 'Şimdilik Geç' : 'Devam Et',
          onPrimary: () => _goToStep(5),
          secondaryLabel: 'Geri',
          onSecondary: () => _goToStep(3),
        );
      case 5:
      default:
        final preorderItems = ref.watch(preorderCartProvider);
        final verifiedPhone = authState.session?.phoneNumber ?? '';
        final canSubmit = draft.isReadyToReview && !_isSubmitting;
        return ReservationStepScaffold(
          title: 'Özet',
          subtitle: 'Bilgilerinizi kontrol edin ve talebinizi gönderin.',
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ReviewStep(
                draft: draft,
                verifiedPhoneNumber: verifiedPhone,
                preorderItems: preorderItems,
                firstNameController: _firstNameController,
                lastNameController: _lastNameController,
                onNameChanged: () => notifier.setContactName(
                  firstName: _firstNameController.text,
                  lastName: _lastNameController.text,
                ),
              ),
              if (_submitError != null) ...[
                const SizedBox(height: AppSpacing.md),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.08),
                    borderRadius: AppRadius.kMedium,
                  ),
                  child: Text(
                    _submitError!,
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.error),
                  ),
                ),
              ],
            ],
          ),
          primaryLabel:
              _isSubmitting ? 'Gönderiliyor...' : 'Rezervasyon Talebini Gönder',
          onPrimary: canSubmit ? _submit : null,
          secondaryLabel: 'Geri',
          onSecondary: _isSubmitting ? null : () => _goToStep(4),
        );
    }
  }
}

class _LoginRequiredScreen extends StatelessWidget {
  const _LoginRequiredScreen({required this.currentLocation});

  final String currentLocation;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rezervasyon')),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.event_seat_rounded,
                    size: 56, color: AppColors.primaryLight),
                const SizedBox(height: AppSpacing.lg),
                const Text(
                  'Rezervasyon oluşturmak için telefon numaranızla giriş yapmanız gerekiyor.',
                  style: AppTypography.bodyLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xl),
                ElevatedButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          LoginScreen(returnTo: currentLocation),
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: const RoundedRectangleBorder(
                        borderRadius: AppRadius.kExtraLarge),
                  ),
                  child: const Text('Giriş Yap'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
