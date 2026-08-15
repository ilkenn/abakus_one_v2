import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/feedback/loading_view.dart';
import '../../../auth/domain/phone_number.dart';
import '../../../orders/domain/models/order_id.dart';
import '../../../orders/presentation/providers/orders_provider.dart'
    show canonicalOrderRepositoryProvider;
import '../../../takeaway/data/submit_takeaway_order_gateway.dart';
import '../../../takeaway/presentation/providers/takeaway_dependencies_provider.dart';
import '../../../takeaway/presentation/providers/takeaway_guest_dependencies_provider.dart';
import '../../domain/models/cart_item.dart';
import '../providers/cart_provider.dart';
import 'order_success_screen.dart';

/// Checkout for a Gel Al QR **guest** order — Faz D.4. No account, no
/// OTP, no `request.auth`-backed customer identity of any kind: this
/// screen only ever asks for what `submitTakeawayOrder`'s guest branch
/// actually needs — a contact snapshot (ad/soyad/telefon) — and the
/// active [TakeawayGuestContext] supplies everything else
/// (`takeawaySessionId`; organization/restaurant/branch scope is derived
/// server-side from that session, never sent by this screen at all).
///
/// No pickup-time picker of any kind — a guest order is always ASAP,
/// forced unconditionally server-side (`submitTakeawayOrder`'s guest
/// branch always writes `pickupMode: 'asap'`/`pickupTime: null`); there is
/// nothing for a picker to do.
///
/// Mirrors `TakeawayCheckoutScreen`'s exact shape (pricing display,
/// duplicate-submission guard, backend-order-snapshot-is-authoritative
/// contract) minus everything identity/pickup-time related, which this
/// scenario doesn't have.
class TakeawayGuestCheckoutScreen extends ConsumerStatefulWidget {
  const TakeawayGuestCheckoutScreen({super.key});

  @override
  ConsumerState<TakeawayGuestCheckoutScreen> createState() =>
      _TakeawayGuestCheckoutScreenState();
}

class _TakeawayGuestCheckoutScreenState
    extends ConsumerState<TakeawayGuestCheckoutScreen> {
  late final TextEditingController _firstNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _phoneController;

  bool _isPreparing = true;
  bool _isSubmitting = false;
  String? _submitError;

  /// Idempotency (Faz D.4 §12): resolved once, asynchronously, in
  /// [initState] — reused from `TakeawayGuestSubmissionKeyStore` if a
  /// prior attempt for this exact session left one pending (e.g. a
  /// browser refresh mid-checkout), otherwise freshly generated and
  /// immediately persisted so a *later* refresh can recover it too. See
  /// that store's own doc comment for exactly what this does and doesn't
  /// protect against.
  late String _submissionKey;

  @override
  void initState() {
    super.initState();
    _firstNameController = TextEditingController();
    _lastNameController = TextEditingController();
    _phoneController = TextEditingController();
    _prepareSubmissionKey();
  }

  Future<void> _prepareSubmissionKey() async {
    final guestContext = ref.read(takeawayGuestContextProvider);
    if (guestContext == null) {
      if (!mounted) return;
      setState(() => _isPreparing = false);
      return;
    }
    final store = ref.read(takeawayGuestSubmissionKeyStoreProvider);
    final pending = await store.readPendingKey(guestContext.sessionId);
    final key = pending ??
        '${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(this)}';
    if (pending == null) {
      await store.persistPendingKey(guestContext.sessionId, key);
    }
    if (!mounted) return;
    setState(() {
      _submissionKey = key;
      _isPreparing = false;
    });
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    return !_isSubmitting &&
        _firstNameController.text.trim().isNotEmpty &&
        _lastNameController.text.trim().isNotEmpty &&
        TurkishPhoneNumber.normalize(_phoneController.text) != null;
  }

  /// Bowl Builder items carry no canonical `MenuProduct` id — mirrors
  /// `TakeawayCheckoutScreen._isBowlCartItem` exactly.
  bool _isBowlCartItem(CartItem item) => item.id.startsWith('custom_bowl_');

  List<TakeawayOrderItem> _buildOrderItems(List<CartItem> cartItems) {
    return [
      for (final item in cartItems)
        if (_isBowlCartItem(item))
          TakeawayBowlItem(
            quantity: item.quantity,
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
        return 'Oturumun bulunamadı. Lütfen QR kodu tekrar okut.';
      case 'failed-precondition':
        return 'Oturumun süresi dolmuş olabilir. Lütfen QR kodu tekrar okut.';
      case 'invalid-argument':
        return 'Sipariş bilgileri geçersiz görünüyor. Lütfen sepeti kontrol et.';
      case 'permission-denied':
      case 'unauthenticated':
        return 'Sipariş gönderilirken bir sorun oluştu. Lütfen QR kodu '
            'tekrar okut.';
      default:
        return 'Sipariş gönderilirken bir sorun oluştu. Lütfen tekrar dene.';
    }
  }

  Future<void> _submitOrder() async {
    if (_isSubmitting) return;
    if (!_canSubmit) return;

    final guestContext = ref.read(takeawayGuestContextProvider);
    if (guestContext == null) {
      setState(() {
        _submitError = 'Oturum bulunamadı. Lütfen QR kodu tekrar okut.';
      });
      return;
    }
    if (guestContext.isExpiredAt(DateTime.now())) {
      setState(() {
        _submitError =
            'Oturumun süresi doldu. Devam etmek için QR kodu tekrar okut.';
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
      final result =
          await ref.read(submitTakeawayOrderGatewayProvider).submitGuestOrder(
                submissionKey: _submissionKey,
                takeawaySessionId: guestContext.sessionId,
                items: _buildOrderItems(cartItems),
                contactFirstName: _firstNameController.text.trim(),
                contactLastName: _lastNameController.text.trim(),
                contactPhone: normalizedPhone,
              );

      // The backend's own canonical order is the single source of truth
      // for what was actually created — read it back rather than
      // reconstructing one client-side from the pre-submit cart estimate
      // (same contract `TakeawayCheckoutScreen` already follows).
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
          .read(takeawayGuestSubmissionKeyStoreProvider)
          .clearPendingKey(guestContext.sessionId);
      ref.read(cartProvider.notifier).clearCart();

      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) => OrderSuccessScreen(
            orderId: order.id.value,
            takeawayBranchName: guestContext.branchDisplayName,
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
    final guestContext = ref.watch(takeawayGuestContextProvider);
    final cartItems = ref.watch(cartProvider);
    final totalPrice = ref.watch(cartTotalPriceProvider);

    if (_isPreparing) {
      return Scaffold(
        appBar: AppBar(title: const Text('Gel Al Siparişi')),
        body: const LoadingView(),
      );
    }

    if (guestContext == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Gel Al Siparişi')),
        body: const _SessionMissing(),
      );
    }

    final isExpired = guestContext.isExpiredAt(DateTime.now());

    return Scaffold(
      appBar: AppBar(title: const Text('Gel Al Siparişi')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            _SectionCard(
              title: 'Şube',
              child: Text(
                guestContext.branchDisplayName,
                style: AppTypography.bodyLarge,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            _SectionCard(
              title: 'Teslim Alma',
              child: Text(
                'Siparişin en kısa sürede hazırlanacak. Kasadan '
                'teslim alabilirsin.',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (isExpired) ...[
              _SessionExpiredBanner(),
              const SizedBox(height: AppSpacing.lg),
            ],
            _SectionCard(
              title: 'İletişim Bilgileri',
              child: Column(
                children: [
                  TextField(
                    controller: _firstNameController,
                    onChanged: (_) => setState(() {}),
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(hintText: 'Ad'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _lastNameController,
                    onChanged: (_) => setState(() {}),
                    textCapitalization: TextCapitalization.words,
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
                      const Text('Toplam', style: AppTypography.titleMedium),
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
                onPressed: (_canSubmit && !isExpired) ? _submitOrder : null,
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

class _SessionExpiredBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error),
      ),
      child: Text(
        'Oturumun süresi doldu. Sipariş verebilmek için kasadaki QR kodu '
        'tekrar okutman gerekiyor.',
        style: AppTypography.bodyMedium.copyWith(color: AppColors.error),
      ),
    );
  }
}

class _SessionMissing extends StatelessWidget {
  const _SessionMissing();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Text(
          'Oturum bulunamadı. Sipariş verebilmek için kasadaki QR kodu '
          'tekrar okutman gerekiyor.',
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
