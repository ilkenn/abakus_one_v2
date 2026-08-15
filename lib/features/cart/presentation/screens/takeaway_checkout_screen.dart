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
import 'order_success_screen.dart';

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

  String _errorMessageFor(String code) {
    switch (code) {
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
          );

      // The backend's own canonical order is the single source of truth
      // for what was actually created (§7 — "backend order snapshot'ı
      // kullanılmalı") — read it back rather than reconstructing one
      // client-side from the pre-submit cart estimate.
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

      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) => OrderSuccessScreen(
            orderId: order.id.value,
            takeawayBranchName: channelContext.branchDisplayName,
            takeawayPickupTime: order.pickupTime,
          ),
        ),
        (route) => route.isFirst,
      );
    } on SubmitTakeawayOrderException catch (error) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _submitError = _errorMessageFor(error.code);
      });
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
                onPressed: _canSubmit ? _submitOrder : null,
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
