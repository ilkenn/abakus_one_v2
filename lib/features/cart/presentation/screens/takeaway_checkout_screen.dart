import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../auth/domain/phone_number.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../loyalty/domain/models/loyalty_account_snapshot.dart';
import '../../../loyalty/domain/models/loyalty_reward.dart';
import '../../../loyalty/presentation/providers/loyalty_providers.dart';
import '../../../orders/domain/models/order_id.dart';
import '../../../orders/domain/models/order_model.dart';
import '../../../orders/domain/models/pickup_time_policy.dart';
import '../../../orders/presentation/providers/orders_provider.dart';
import '../../../takeaway/data/submit_takeaway_order_gateway.dart';
import '../../../../core/auth/real_customer_check.dart';
import '../../../takeaway/presentation/providers/takeaway_dependencies_provider.dart';
import '../../domain/models/cart_item.dart';
import '../providers/cart_provider.dart';
import '../providers/shopping_channel_provider.dart';
import '../widgets/boncuk_redemption_card.dart';
import '../widgets/catalog_reward_card.dart';
import 'order_success_screen.dart';

/// Boncuk Loyalty Program P4-E-B (2026-08-22) — the presentation-only,
/// NON-AUTHORITATIVE estimate of the maximum whole Boncuk this order can
/// use right now, mirroring `functions/src/loyaltyRedemption.ts`'s own
/// locked `calculateBoncukRedemption` cap formula exactly (P4-B §3), using
/// the SAME approximate cart total this screen already labels
/// "tahminidir" elsewhere. Integer/minor-unit arithmetic throughout — the
/// cart's own `double` TL total is converted to minor units exactly once,
/// then every further step uses `~/` (never floating point) — never a
/// separate pricing engine, never a claim of exactness beyond what the
/// existing cart estimate already is. `submitTakeawayOrder` revalidates
/// everything server-side (P4-B); this value drives UI bounds only.
int computeClientEstimatedMaxBoncuk(
  LoyaltyAccountSnapshot snapshot,
  double cartTotalPriceTl,
) {
  if (snapshot.spendableBalance <= 0 || snapshot.boncukDebt > 0) return 0;
  if (snapshot.redemptionValueMinorUnitsPerBoncuk <= 0) return 0;
  final estimatedGrandTotalMinorUnits = (cartTotalPriceTl * 100).round();
  final maxRedemptionValueMinorUnits = estimatedGrandTotalMinorUnits *
      snapshot.maxRedemptionBasisPoints ~/
      10000;
  final maxUsableBoncukByOrderCap = maxRedemptionValueMinorUnits ~/
      snapshot.redemptionValueMinorUnitsPerBoncuk;
  return snapshot.spendableBalance < maxUsableBoncukByOrderCap
      ? snapshot.spendableBalance
      : maxUsableBoncukByOrderCap;
}

/// Checkout for an authenticated in-app Gel Al (takeaway) order.
///
/// **Faz D.3.1 migration**: this screen no longer builds an `Order`/talks
/// to `CanonicalOrderRepository.submitOrder` directly — it sends only the
/// customer's *intent* (branch, product/bowl selections, pickup time,
/// contact snapshot, an idempotency key) to the server-authoritative
/// `submitTakeawayOrder` Cloud Function (via `SubmitTakeawayOrderGateway`)
/// and reads the resulting canonical order back. `unitPrice`/`subtotal`/
/// `grandTotal`/`customerId` are never client-selected — there is no
/// field in the gateway's own request shape for any of them; `customerId`
/// is derived server-side from the caller's own Firebase Auth token.
/// `docs/decisions.md` ADR-027 Faz D.3.1 records the full migration and
/// why the old `firestore.rules` direct-create path this screen used to
/// rely on (Faz C) is now removed.
///
/// A separate, self-contained screen mirroring `DineInCheckoutScreen`'s
/// exact shape/reasoning (not a conditional branch inside the 900-line
/// delivery `CheckoutScreen`): this screen only ever asks for what a Gel
/// Al order actually needs — branch, pickup time, contact snapshot — no
/// delivery address, no cutlery/courier preferences, no table wording.
///
/// Reached only from `CartScreen`'s checkout button when
/// `shoppingChannelProvider.channel == OrderChannel.takeaway` and no
/// dine-in table context is active — `TakeawayBranchSelectionScreen` is
/// this flow's actual entry point (auth-gated there, not re-checked here,
/// since a signed-out session could not have reached this far without also
/// failing the submit-time identity requirement below — now enforced
/// server-side, not merely by this screen's own guard).
class TakeawayCheckoutScreen extends ConsumerStatefulWidget {
  const TakeawayCheckoutScreen({super.key});

  @override
  ConsumerState<TakeawayCheckoutScreen> createState() =>
      _TakeawayCheckoutScreenState();
}

class _TakeawayCheckoutScreenState
    extends ConsumerState<TakeawayCheckoutScreen> {
  static const List<int> _quickPickupMinutesOptions = [20, 30, 45, 60];

  late final TextEditingController _firstNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _phoneController;

  DateTime? _selectedPickupTime;
  bool _isSubmitting = false;
  String? _submitError;

  /// Boncuk Loyalty Program P4-E-B (2026-08-22) — local, screen-owned
  /// interaction state ONLY (per the locked state-management decision: no
  /// new checkout controller/provider). Server data continues to come
  /// exclusively from [loyaltySnapshotProvider], watched fresh in [build];
  /// nothing here duplicates it. [_boncukUsageEnabled]/
  /// [_selectedBoncukAmount] are the customer's own explicit choices —
  /// never silently mutated to a different NONZERO value by a cart/
  /// snapshot change (see [_handleBoncukEstimateMightHaveChanged]); the one
  /// exception is resetting both to off/0 when the estimated max reaches
  /// exactly zero, which is an explicit, locked instruction (P4-E-B §9),
  /// not a silent substitution.
  bool _boncukUsageEnabled = false;
  int _selectedBoncukAmount = 0;

  /// Boncuk Loyalty Program P7-C (2026-08-24) — the customer's own explicit
  /// catalog-reward choice, `null` meaning none. Mutually exclusive with
  /// [_boncukUsageEnabled] by construction: [_onBoncukToggle] clears this
  /// when turning cash redemption on, [_onRewardSelect] clears
  /// [_boncukUsageEnabled]/[_selectedBoncukAmount] when a reward is picked
  /// — never both set at once, matching the server's own fail-closed
  /// stacking rejection.
  String? _selectedRewardId;

  /// Idempotency (Faz D.3.1): generated once, on screen init, then reused
  /// on every retry within this screen's lifetime — the backend's own
  /// `sha256(actorUid|submissionKey)` derivation (`docs/decisions.md`
  /// ADR-027 Faz D.3) is now the single, authoritative idempotency
  /// mechanism; this screen no longer mints/tracks an `OrderId` itself
  /// (there is nothing left for the old "check if the order already
  /// exists" catch-block fallback to do — a retry with the same
  /// `_submissionKey` safely reuses the backend's own existing order
  /// either way, so a raw thrown exception here just means "show an
  /// error, let the user retry").
  late final String _submissionKey;

  /// Which quick-pickup chip is currently selected, tracked directly
  /// rather than re-derived from `_selectedPickupTime.difference(DateTime
  /// .now())` — that comparison drifts by design (the buffer below, plus
  /// ordinary elapsed time) and would make a just-tapped chip stop
  /// looking selected within the same second.
  int? _selectedQuickOption;

  @override
  void initState() {
    super.initState();
    final session = ref.read(authProvider).session;
    _firstNameController = TextEditingController();
    _lastNameController = TextEditingController();
    // `AuthSession.phoneNumber` is stored normalized (`+905XXXXXXXXX` — see
    // `AuthNotifier.requestOtp`'s own `TurkishPhoneNumber.normalize` call);
    // this field shows/edits only the 10-digit local part (mirrors
    // `TakeawayGuestCheckoutScreen`'s "+90 " prefix + local-digits UI), so
    // the `+90` prefix is stripped back off here before pre-filling.
    final sessionPhone = session?.phoneNumber;
    _phoneController = TextEditingController(
      text: sessionPhone != null && sessionPhone.startsWith('+90')
          ? sessionPhone.substring(3)
          : '',
    );
    _submissionKey =
        '${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(this)}';
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  /// A small buffer beyond the bare `Duration(minutes: minutesFromNow)` —
  /// without it, a chip computed at exactly the minimum boundary
  /// (`PickupTimePolicy`'s own `>=` inclusive boundary) would flip invalid
  /// the moment any real time elapses before submission (filling in
  /// contact fields, a slow device, network latency), since
  /// `_isPickupTimeValid` re-measures against a fresh `DateTime.now()` on
  /// every rebuild. This buffer is a client-side UX convenience only — it
  /// never affects `PickupTimePolicy`'s own exact-boundary contract or
  /// `submitTakeawayOrder`'s server-side NOW+20 enforcement (the actual
  /// authority since Faz D.3.1 — this screen's own check is UX-only, per
  /// direct instruction), both of which stay exactly `>= 20 minutes`.
  static const Duration _selectionBuffer = Duration(minutes: 1);

  void _selectQuickPickup(int minutesFromNow) {
    setState(() {
      _selectedPickupTime = DateTime.now()
          .add(Duration(minutes: minutesFromNow))
          .add(_selectionBuffer);
      _selectedQuickOption = minutesFromNow;
      _submitError = null;
    });
  }

  /// Boncuk Loyalty P4-E-B — the customer explicitly turning Boncuk usage
  /// on/off. Off means the selected amount is effectively 0 (§6's own
  /// rule); on seeds the minimum whole amount (1) if nothing was already
  /// selected — never leaves the toggle "on" with a 0 amount, which would
  /// be an invalid intermediate state the stepper/submit guard would then
  /// have to special-case.
  void _onBoncukToggle(bool value) {
    setState(() {
      _boncukUsageEnabled = value;
      _selectedBoncukAmount =
          value ? (_selectedBoncukAmount > 0 ? _selectedBoncukAmount : 1) : 0;
      // Boncuk Loyalty P7-C — mutual exclusivity: turning cash redemption
      // on clears any catalog-reward selection.
      if (value) _selectedRewardId = null;
      _submitError = null;
    });
  }

  /// Boncuk Loyalty Program P7-C (2026-08-24) — the customer picking (or
  /// un-picking) a catalog reward. Mutual exclusivity: selecting a reward
  /// clears any active cash-Boncuk selection.
  void _onRewardSelect(String? rewardId) {
    setState(() {
      _selectedRewardId = rewardId;
      if (rewardId != null) {
        _boncukUsageEnabled = false;
        _selectedBoncukAmount = 0;
      }
      _submitError = null;
    });
  }

  void _onBoncukAmountChanged(int newAmount) {
    setState(() {
      _selectedBoncukAmount = newAmount;
      _submitError = null;
    });
  }

  void _onBoncukUseMax() {
    final snapshot = ref.read(loyaltySnapshotProvider).valueOrNull;
    if (snapshot == null) return;
    final max = computeClientEstimatedMaxBoncuk(
      snapshot,
      ref.read(cartTotalPriceProvider),
    );
    setState(() {
      _boncukUsageEnabled = max > 0;
      _selectedBoncukAmount = max > 0 ? max : 0;
      _submitError = null;
    });
  }

  /// Boncuk Loyalty P4-E-B §9/§10 — reacts to a cart total or loyalty
  /// snapshot change while Boncuk usage is on. **Never silently clamps
  /// [_selectedBoncukAmount] down to a smaller nonzero value** — if the
  /// estimated max shrinks but stays above zero, [_selectedBoncukAmount]
  /// is left exactly as the customer chose it; [build]'s own
  /// `boncukSelectionInvalid` computation (derived, not stored) is what
  /// then disables submission and shows the recovery notice/actions. The
  /// ONE state mutation this method performs is the explicitly locked
  /// exception: if the estimated max reaches exactly zero, Boncuk usage is
  /// turned off and the selection reset to 0 — there is nothing a
  /// stepper/MAX action could recover to in that case.
  void _handleBoncukEstimateMightHaveChanged() {
    if (!_boncukUsageEnabled) return;
    final snapshot = ref.read(loyaltySnapshotProvider).valueOrNull;
    if (snapshot == null) return;
    final max = computeClientEstimatedMaxBoncuk(
      snapshot,
      ref.read(cartTotalPriceProvider),
    );
    if (max <= 0) {
      setState(() {
        _boncukUsageEnabled = false;
        _selectedBoncukAmount = 0;
      });
    }
  }

  /// Boncuk Loyalty Program P7-C (2026-08-24) — the catalog-reward sibling
  /// of [_handleBoncukEstimateMightHaveChanged]: if the cart changes such
  /// that the currently-selected reward's product is no longer present
  /// (removed, quantity change doesn't matter — only presence does),
  /// there is no "stepper/MAX" recovery for a reward pick the way there is
  /// for a Boncuk amount, so the only correct behavior is to clear the
  /// now-impossible selection outright, never silently leave it selected
  /// and pointing at nothing.
  void _handleCartMightHaveInvalidatedReward() {
    final rewardId = _selectedRewardId;
    if (rewardId == null) return;
    final rewards = ref.read(loyaltyRewardCatalogProvider).valueOrNull;
    final reward = rewards?.where((r) => r.rewardId == rewardId).firstOrNull;
    final cartProductIds = ref
        .read(cartProvider)
        .where((item) => !_isBowlCartItem(item))
        .map((item) => item.id)
        .toSet();
    if (reward == null || !reward.isEligibleForCart(cartProductIds)) {
      setState(() => _selectedRewardId = null);
    }
  }

  bool get _isPickupTimeValid {
    final pickupTime = _selectedPickupTime;
    if (pickupTime == null) return false;
    return PickupTimePolicy.isValid(pickupTime, DateTime.now());
  }

  bool get _canSubmit {
    return _isPickupTimeValid &&
        _firstNameController.text.trim().isNotEmpty &&
        _lastNameController.text.trim().isNotEmpty &&
        TurkishPhoneNumber.normalize(_phoneController.text) != null &&
        !_isSubmitting;
  }

  /// Bowl Builder items are the one `CartItem` shape without a canonical
  /// `MenuProduct` id — `bowl_builder_screen.dart`'s own `_addToCart`
  /// mints `'custom_bowl_<timestamp>'` as the cart id, which this check
  /// reuses as the sole existing signal distinguishing the two cases
  /// (`CartItem` itself carries no explicit product/bowl discriminator
  /// field — adding one is a broader `CartItem`-shape change touching
  /// every other cart call site, out of this migration's scope).
  bool _isBowlCartItem(CartItem item) => item.id.startsWith('custom_bowl_');

  List<TakeawayOrderItem> _buildOrderItems(List<CartItem> cartItems) {
    return [
      for (final item in cartItems)
        if (_isBowlCartItem(item))
          TakeawayBowlItem(
            quantity: item.quantity,
            // A quantity-N ingredient already appears as N separate
            // `SelectedModifier` entries (`bowlBuilderSelectedModifiersProvider`'s
            // own existing convention) — this flat list needs no
            // aggregation step to match `submitTakeawayOrder`'s own
            // per-occurrence ingredient resolution.
            ingredientIds: [
              for (final modifier in item.selectedModifiers) modifier.optionId,
            ],
            note: item.note,
          )
        else
          TakeawayProductItem(
            productId: item.id,
            quantity: item.quantity,
            selectedModifiers: [
              for (final modifier in item.selectedModifiers)
                (groupId: modifier.groupId, optionId: modifier.optionId),
            ],
            note: item.note,
          ),
    ];
  }

  /// Boncuk Loyalty P4-E-B §13 — a Boncuk-specific rejection is mapped from
  /// [SubmitTakeawayOrderException.boncukErrorReason] (the stable,
  /// machine-readable server reason), NEVER inferred from [error]'s `code`
  /// alone: `invalid-argument`/`failed-precondition` are also used for
  /// entirely unrelated validation in this same callable (contact fields,
  /// pickup time, branch scope, ...), so `code` alone cannot safely
  /// distinguish "your Boncuk selection is now invalid" from any of those.
  String _errorMessageFor(SubmitTakeawayOrderException error) {
    final boncukReason = error.boncukErrorReason;
    if (boncukReason != null) {
      switch (boncukReason) {
        case 'boncuk/exceeds-max-usable':
          return 'Boncuk bakiyen veya kullanabileceğin miktar değişti. '
              'Bilgileri güncelledik; tekrar seçim yap.';
        case 'boncuk/account-unavailable':
          return 'Boncuk hesabına şu anda ulaşılamıyor. Tekrar deneyebilir '
              'veya Boncuk kullanmadan devam edebilirsin.';
        case 'boncuk/policy-unavailable':
          return 'Boncuk kullanımı şu anda geçici olarak kullanılamıyor. '
              'Biraz sonra tekrar deneyebilirsin.';
        // Boncuk Loyalty P7-C (2026-08-24) — catalog-reward-specific
        // reasons, same shared `boncukErrorReason` field/namespace.
        case 'catalogReward/reward-not-found':
        case 'catalogReward/reward-not-currently-valid':
          return 'Seçtiğin ödül artık kullanılamıyor. Lütfen tekrar seçim '
              'yap veya ödül kullanmadan devam et.';
        case 'catalogReward/product-not-in-cart':
          return 'Seçtiğin ödül için uygun bir ürün sepetinde bulunamadı. '
              'Lütfen sepetini kontrol et.';
        case 'catalogReward/insufficient-balance':
          return 'Bu ödül için yeterli Boncuk bakiyen yok. Bilgileri '
              'güncelledik; ödül kullanmadan devam edebilirsin.';
        case 'catalogReward/account-unavailable':
          return 'Boncuk hesabına şu anda ulaşılamıyor. Tekrar deneyebilir '
              'veya ödül kullanmadan devam edebilirsin.';
        case 'catalogReward/benefit-stacking-not-allowed':
          return 'Aynı anda hem Boncuk hem ödül kullanılamaz. Lütfen '
              'birini seç.';
        default:
          return 'Boncuk kullanılırken bir sorun oluştu. Boncuk kullanmadan '
              'devam edebilirsin.';
      }
    }
    switch (error.code) {
      case 'not-found':
        return 'Şube bulunamadı. Lütfen şube seçimine geri dön.';
      case 'failed-precondition':
        return 'Seçilen saat veya şube şu anda uygun olmayabilir. '
            'Lütfen tekrar dene.';
      case 'invalid-argument':
        return 'Sipariş bilgileri geçersiz görünüyor. Lütfen sepeti kontrol et.';
      case 'permission-denied':
      case 'unauthenticated':
        return 'Sipariş gönderilirken bir sorun oluştu. Lütfen tekrar giriş yap.';
      default:
        return 'Sipariş gönderilirken bir sorun oluştu. Lütfen tekrar dene.';
    }
  }

  Future<void> _submitOrder() async {
    if (_isSubmitting) return;
    if (!_canSubmit) return;

    // Defense-in-depth (P4-E-B §9) — the submit button is already disabled
    // whenever the UI's own derived `boncukSelectionInvalid` is true; this
    // re-checks the same condition against a freshly-read snapshot right
    // before sending, rather than trusting only the last-built widget
    // state. Never sends a Boncuk amount the customer didn't explicitly
    // choose and that still fits the latest estimate.
    if (_boncukUsageEnabled) {
      final snapshot = ref.read(loyaltySnapshotProvider).valueOrNull;
      final max = snapshot == null
          ? 0
          : computeClientEstimatedMaxBoncuk(
              snapshot, ref.read(cartTotalPriceProvider));
      if (_selectedBoncukAmount <= 0 || _selectedBoncukAmount > max) {
        return;
      }
    }

    // Boncuk Loyalty P7-C — the same defense-in-depth discipline for a
    // catalog-reward selection: re-verify against the freshest cart/reward
    // data right before sending, never trusting only the last-built widget
    // state. The server re-validates everything again regardless; this
    // only prevents sending an obviously-stale selection.
    if (_selectedRewardId != null) {
      final rewards = ref.read(loyaltyRewardCatalogProvider).valueOrNull;
      final cartProductIds = ref
          .read(cartProvider)
          .where((item) => !_isBowlCartItem(item))
          .map((item) => item.id)
          .toSet();
      final stillEligible = rewards != null &&
          rewards.any((r) =>
              r.rewardId == _selectedRewardId &&
              r.isEligibleForCart(cartProductIds));
      if (!stillEligible) {
        setState(() => _selectedRewardId = null);
        return;
      }
    }

    final channelContext = ref.read(shoppingChannelProvider);
    final branchId = channelContext.branchId;
    final restaurantId = channelContext.restaurantId;
    if (branchId == null || restaurantId == null) {
      setState(() {
        _submitError =
            'Şube bilgisi bulunamadı. Lütfen şube seçimine geri dön.';
      });
      return;
    }

    final authSession = ref.read(authProvider).session;
    final isReal = isRealCustomer(ref.read(authProvider));
    if (authSession == null || !isReal) {
      setState(() {
        _submitError =
            'Sipariş gönderilirken bir sorun oluştu. Lütfen tekrar giriş yap.';
      });
      return;
    }

    final cartItems = ref.read(cartProvider);
    if (cartItems.isEmpty) {
      setState(() => _submitError = 'Sepetin boş.');
      return;
    }

    final normalizedPhone = TurkishPhoneNumber.normalize(_phoneController.text);
    if (normalizedPhone == null) {
      setState(() => _submitError = 'Geçerli bir telefon numarası gir.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    try {
      final result = await ref
          .read(submitTakeawayOrderGatewayProvider)
          .submitAuthenticatedOrder(
            submissionKey: _submissionKey,
            restaurantId: restaurantId,
            branchId: branchId,
            pickupTime: _selectedPickupTime!,
            items: _buildOrderItems(cartItems),
            contactFirstName: _firstNameController.text.trim(),
            contactLastName: _lastNameController.text.trim(),
            contactPhone: normalizedPhone,
            requestedBoncukAmount:
                _boncukUsageEnabled ? _selectedBoncukAmount : 0,
            selectedRewardId: _selectedRewardId,
          );

      // The backend's own canonical order is the single source of truth
      // for what was actually created (§7 — "backend order snapshot'ı
      // kullanılmalı") — read it back rather than reconstructing one
      // client-side from the pre-submit cart estimate. This is also the
      // ONLY source `boncukRedemption`/`selectedBenefitType` below come
      // from (P4-E-B §14) — never the pre-submit local estimate.
      final order = await ref
          .read(canonicalOrderRepositoryProvider)
          .findById(OrderId(result.orderId));
      if (order == null) {
        throw StateError(
          'submitTakeawayOrder succeeded but the resulting order could not '
          'be read back (orderId: ${result.orderId}).',
        );
      }

      await ref
          .read(ordersProvider.notifier)
          .addOrder(OrderModel.fromCanonicalOrder(order));
      ref.read(cartProvider.notifier).clearCart();

      // Boncuk Loyalty P4-E-B §14 — redemption occurs at submission time,
      // not at completed-order earning; refresh the customer's displayed
      // balance now rather than waiting for a later screen to happen to
      // re-fetch it. Reuses the existing provider — no new loyalty cache.
      // Boncuk Loyalty P7-C — a catalog-reward redemption debits the same
      // account, so the reward catalog's own eligibility-by-balance state
      // (not tracked here, but the snapshot IS) is refreshed identically.
      ref.invalidate(loyaltySnapshotProvider);
      if (order.catalogReward != null) {
        ref.invalidate(loyaltyRewardCatalogProvider);
      }

      if (!mounted) return;
      final boncukRedemption = order.boncukRedemption;
      final catalogReward = order.catalogReward;
      // Server-confirmed only (P7-C) — cross-referenced from the SAME
      // canonical order's own `lines`, never a separate catalog lookup and
      // never the pre-submit cart's own product name.
      final catalogRewardProductName = catalogReward == null
          ? null
          : order.lines
              .firstWhere(
                  (line) => line.productId == catalogReward.redeemedProductId)
              .productName;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) => OrderSuccessScreen(
            orderId: order.id.value,
            takeawayBranchName: channelContext.branchDisplayName,
            takeawayPickupTime: order.pickupTime,
            orderTotalMinorUnits: order.pricing.grandTotal.minorUnits,
            boncukUsed: boncukRedemption?.boncukUsed,
            boncukValueMinorUnits: boncukRedemption?.valueMinorUnits,
            remainingPayableMinorUnits:
                boncukRedemption?.remainingPayableMinorUnits,
            catalogRewardTitle: catalogReward?.title,
            catalogRewardBoncukCost: catalogReward?.boncukCost,
            catalogRewardRedeemedProductName: catalogRewardProductName,
            catalogRewardCoveredValueMinorUnits:
                catalogReward?.coveredValueMinorUnits,
          ),
        ),
        (route) => route.isFirst,
      );
    } on SubmitTakeawayOrderException catch (error) {
      if (!mounted) return;
      final isBoncukError = error.boncukErrorReason != null;
      setState(() {
        _isSubmitting = false;
        _submitError = _errorMessageFor(error);
        if (isBoncukError) {
          // CRITICAL (§13) — never auto-resubmit without Boncuk. Turning
          // the selection off makes the screen immediately submittable
          // again WITHOUT Boncuk, but the customer must tap "Siparişi
          // Ver" themselves; nothing here resubmits on their behalf.
          // Boncuk Loyalty P7-C — the same reset covers a catalog-reward
          // rejection too (shared `boncukErrorReason` namespace/signal).
          _boncukUsageEnabled = false;
          _selectedBoncukAmount = 0;
          _selectedRewardId = null;
        }
      });
      if (isBoncukError) {
        ref.invalidate(loyaltySnapshotProvider);
        ref.invalidate(loyaltyRewardCatalogProvider);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _submitError =
            'Sipariş gönderilirken bir sorun oluştu. Lütfen tekrar dene.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final channelContext = ref.watch(shoppingChannelProvider);
    final cartItems = ref.watch(cartProvider);
    final totalPrice = ref.watch(cartTotalPriceProvider);
    final loyaltySnapshotAsync = ref.watch(loyaltySnapshotProvider);
    final rewardsAsync = ref.watch(loyaltyRewardCatalogProvider);

    // Boncuk Loyalty P4-E-B §9/§10 — react to a cart-total or loyalty
    // snapshot change while Boncuk usage is on. `ref.listen` (not
    // `ref.watch`) is used here specifically because this needs to run a
    // side effect (`setState` via `_handleBoncukEstimateMightHaveChanged`)
    // in response to a change, never during `build` itself.
    ref.listen<double>(cartTotalPriceProvider, (previous, next) {
      _handleBoncukEstimateMightHaveChanged();
    });
    ref.listen<AsyncValue<LoyaltyAccountSnapshot>>(loyaltySnapshotProvider,
        (previous, next) {
      _handleBoncukEstimateMightHaveChanged();
    });
    // Boncuk Loyalty P7-C — same reasoning, for a catalog-reward selection
    // the cart itself (not just the total) can invalidate.
    ref.listen<List<CartItem>>(cartProvider, (previous, next) {
      _handleCartMightHaveInvalidatedReward();
    });
    ref.listen<AsyncValue<List<LoyaltyReward>>>(loyaltyRewardCatalogProvider,
        (previous, next) {
      _handleCartMightHaveInvalidatedReward();
    });

    final cartProductIds = cartItems
        .where((item) => !_isBowlCartItem(item))
        .map((item) => item.id)
        .toSet();

    final clientEstimatedMaxBoncuk = loyaltySnapshotAsync.maybeWhen(
      data: (snapshot) => computeClientEstimatedMaxBoncuk(snapshot, totalPrice),
      orElse: () => 0,
    );
    // Derived, never stored — this is deliberately NOT a mutable field:
    // recomputing it fresh every build is what guarantees it can never
    // drift from `_selectedBoncukAmount`/the latest snapshot (P4-E-B §9).
    final boncukSelectionInvalid =
        _boncukUsageEnabled && _selectedBoncukAmount > clientEstimatedMaxBoncuk;
    final canSubmit = _canSubmit && !boncukSelectionInvalid;

    return Scaffold(
      appBar: AppBar(title: const Text('Gel Al Siparişi')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            _SectionCard(
              title: 'Şube',
              child: Text(
                channelContext.branchDisplayName ?? '—',
                style: AppTypography.bodyLarge,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            _SectionCard(
              title: 'Teslim Alma Zamanı',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      for (final minutes in _quickPickupMinutesOptions)
                        _PickupChip(
                          label: '$minutes dk sonra',
                          isSelected: _selectedQuickOption == minutes,
                          onTap: () => _selectQuickPickup(minutes),
                        ),
                    ],
                  ),
                  if (_selectedPickupTime != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Seçilen saat: '
                      '${_selectedPickupTime!.hour.toString().padLeft(2, '0')}:'
                      '${_selectedPickupTime!.minute.toString().padLeft(2, '0')}',
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'En erken şimdiden ${PickupTimePolicy.minimumLeadTime.inMinutes} '
                    'dakika sonra teslim alabilirsin.',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            _SectionCard(
              title: 'İletişim Bilgileri',
              child: Column(
                children: [
                  TextField(
                    controller: _firstNameController,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(hintText: 'Ad'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _lastNameController,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(hintText: 'Soyad'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _phoneController,
                    onChanged: (_) => setState(() {}),
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    decoration: const InputDecoration(
                      prefixText: '+90 ',
                      hintText: '5XX XXX XX XX',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            _SectionCard(
              title: 'Ürünler',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final item in cartItems)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              '${item.quantity}x ${item.name}',
                              style: AppTypography.bodyMedium,
                            ),
                          ),
                          Text(
                            '${item.totalRowPrice.toStringAsFixed(0)} TL',
                            style: AppTypography.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Toplam',
                        style: AppTypography.titleMedium,
                      ),
                      Text(
                        '${totalPrice.toStringAsFixed(0)} TL',
                        style: AppTypography.titleLarge.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Gel Al fiyatlarına ambalaj maliyeti dahildir.',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Yukarıdaki tutar tahminidir; kesin tutar siparişin '
                    'onaylanmasıyla belirlenir.',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            // Boncuk Loyalty P7-C (2026-08-24) — mutual exclusivity with
            // the catalog-reward card below: selecting a reward REMOVES
            // this card entirely (never just visually disables it),
            // matching the locked "selecting catalog reward disables/
            // removes Boncuk cash redemption selection" requirement.
            // `BoncukRedemptionCard` itself is unchanged — also shared by
            // `DeliveryCheckoutScreen`, so no new required param was added
            // to it for this takeaway-only phase.
            if (_selectedRewardId == null)
              BoncukRedemptionCard(
                snapshotAsync: loyaltySnapshotAsync,
                enabled: _boncukUsageEnabled,
                selectedAmount: _selectedBoncukAmount,
                maxUsableBoncuk: clientEstimatedMaxBoncuk,
                selectionInvalid: boncukSelectionInvalid,
                controlsFrozen: _isSubmitting,
                cartTotalPriceTl: totalPrice,
                onToggle: _onBoncukToggle,
                onAmountChanged: _onBoncukAmountChanged,
                onUseMax: _onBoncukUseMax,
                onRetry: () => ref.invalidate(loyaltySnapshotProvider),
              ),
            const SizedBox(height: AppSpacing.lg),
            CatalogRewardCard(
              rewardsAsync: rewardsAsync,
              cartProductIds: cartProductIds,
              selectedRewardId: _selectedRewardId,
              boncukCashRedemptionActive: _boncukUsageEnabled,
              controlsFrozen: _isSubmitting,
              onSelect: _onRewardSelect,
              onRetry: () => ref.invalidate(loyaltyRewardCatalogProvider),
            ),
            if (_submitError != null) ...[
              const SizedBox(height: AppSpacing.lg),
              Text(
                _submitError!,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.error,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: canSubmit ? _submitOrder : null,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.md,
                  ),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.onPrimary,
                        ),
                      )
                    : const Text('Siparişi Ver'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTypography.titleMedium.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }
}

class _PickupChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _PickupChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.surfaceVariant,
          borderRadius: AppRadius.kPill,
        ),
        child: Text(
          label,
          style: AppTypography.labelLarge.copyWith(
            color: isSelected ? AppColors.onPrimary : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
