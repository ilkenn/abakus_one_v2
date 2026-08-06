import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme_constants.dart';
import '../../../../shared/models/money.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../profile/domain/models/address_model.dart';
import '../../../profile/presentation/providers/addresses_provider.dart';
import '../../../profile/presentation/screens/address_form_screen.dart';
import '../../../profile/presentation/providers/saved_cards_provider.dart';
import '../../../restaurant/presentation/providers/restaurant_status_provider.dart';
import '../../../restaurant/presentation/providers/delivery_zone_provider.dart';
import '../../../orders/domain/models/order_model.dart';
import '../../../orders/presentation/providers/orders_provider.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../providers/cart_provider.dart';
import 'order_success_screen.dart';

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  AddressModel? _selectedAddress;
  String? _selectedPaymentMethod;
  String? _selectedSavedCardId;

  late final TextEditingController _noteController;
  late final TextEditingController _customLeaveDescriptionController;
  bool _ringBell = true;
  bool _leaveAtDoor = false;
  String _leaveAtDoorLocation = 'Kapının önü';
  bool _contactlessDelivery = false;
  bool _courierCanCall = true;

  String _deliveryTimingType = 'immediate';
  DateTime? _scheduledDeliveryDateTime;
  String? _timingError;

  String? _selectedCutleryPreference;
  bool _showCutleryError = false;

  late final TextEditingController _couponController;
  String? _appliedCouponCode;
  String? _couponError;
  double _discountAmount = 0.0;

  static const List<String> _paymentMethods = [
    'Online Kredi/Banka Kartı',
    'Kapıda Kredi Kartı',
    'Kapıda Nakit',
  ];

  static const List<String> _leaveOptions = [
    'Kapının önü',
    'Güvenlik',
    'Resepsiyon',
    'Özel açıklama',
  ];

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController();
    _customLeaveDescriptionController = TextEditingController();
    _couponController = TextEditingController();
    _selectedPaymentMethod = _paymentMethods.first;
  }

  @override
  void dispose() {
    _noteController.dispose();
    _customLeaveDescriptionController.dispose();
    _couponController.dispose();
    super.dispose();
  }

  void _applyCoupon(double subTotal, double deliveryFee) {
    setState(() {
      _couponError = null;
      final code = _couponController.text.trim().toUpperCase();

      if (code.isEmpty) {
        _couponError = 'Lütfen bir kupon kodu giriniz';
        return;
      }

      if (_appliedCouponCode != null) {
        _couponError = 'Aynı anda yalnızca bir kupon kullanılabilir';
        return;
      }

      if (code == 'ABAKUS10') {
        _appliedCouponCode = 'ABAKUS10';
        _discountAmount = subTotal * 0.10;
      } else if (code == 'ILKSIPARIS') {
        _appliedCouponCode = 'ILKSIPARIS';
        _discountAmount = 100.0;
      } else if (code == 'UCRETSIZ') {
        _appliedCouponCode = 'UCRETSIZ';
        _discountAmount = deliveryFee;
      } else {
        _couponError = 'Geçersiz kupon kodu';
      }
    });
  }

  void _removeCoupon() {
    setState(() {
      _appliedCouponCode = null;
      _discountAmount = 0.0;
      _couponController.clear();
      _couponError = null;
    });
  }

  String _formatDateTime(DateTime? dateTime) {
    if (dateTime == null) return '';
    final day = dateTime.day.toString().padLeft(2, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final year = dateTime.year;
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$day.$month.$year $hour:$minute';
  }

  Future<void> _pickScheduledDateTime() async {
    final DateTime now = DateTime.now();

    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 7)),
    );

    if (pickedDate == null) return;

    if (!mounted) return;
    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );

    if (pickedTime == null) return;

    if (pickedTime.hour < 9 || pickedTime.hour >= 22) {
      setState(() {
        _timingError =
            'Restoranımız 09:00 - 22:00 saatleri arasında hizmet vermektedir.';
        _scheduledDeliveryDateTime = null;
      });
      return;
    }

    final DateTime selectedFullDateTime = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    if (selectedFullDateTime.isBefore(now)) {
      setState(() {
        _timingError = 'Geçmiş bir tarih veya saat seçemezsiniz.';
        _scheduledDeliveryDateTime = null;
      });
      return;
    }

    setState(() {
      _timingError = null;
      _scheduledDeliveryDateTime = selectedFullDateTime;
    });
  }

  /// Builds the human-readable checkout-preferences note folded into
  /// [Order.customerNote] — Sprint 9D (`docs/decisions.md` ADR-026).
  /// [OrderModel]'s individual delivery-preference/scheduling fields have
  /// no structured equivalent on the canonical [Order] aggregate; this is
  /// the documented, deliberate interim choice (see
  /// `OrderModel.fromCanonicalOrder`'s own doc comment) — the information
  /// is preserved as readable text, not silently dropped.
  String _buildPreferencesNote() {
    final lines = <String>[
      _selectedCutleryPreference == 'want'
          ? 'Servis malzemesi: İstiyor'
          : 'Servis malzemesi: İstemiyor',
      if (_ringBell) 'Zil çalınsın',
      if (_contactlessDelivery) 'Temassız teslimat',
      if (!_courierCanCall) 'Kurye aramasın',
      if (_leaveAtDoor)
        'Kapıya bırak: $_leaveAtDoorLocation'
            '${_leaveAtDoorLocation == 'Özel açıklama' ? ' (${_customLeaveDescriptionController.text.trim()})' : ''}',
      if (_deliveryTimingType == 'scheduled' &&
          _scheduledDeliveryDateTime != null)
        'Planlanan teslimat: ${_formatDateTime(_scheduledDeliveryDateTime)}',
      if (_noteController.text.trim().isNotEmpty)
        'Not: ${_noteController.text.trim()}',
    ];
    return lines.join(' • ');
  }

  Future<void> _submitOrder(
    double deliveryFee,
    double discountAmount,
  ) async {
    if (_selectedCutleryPreference == null) {
      setState(() {
        _showCutleryError = true;
      });
      return;
    }

    if (_deliveryTimingType == 'scheduled' &&
        _scheduledDeliveryDateTime == null) {
      setState(() {
        _timingError =
            'Lütfen ileri teslimat için geçerli bir tarih ve saat seçiniz.';
      });
      return;
    }

    final cartItems = ref.read(cartProvider);
    final session = ref.read(authProvider);
    final customerId = session.isAuthenticated ? session.session?.uid : null;

    final order = await ref.read(submitCustomerOrderProvider).call(
          cartItems: cartItems,
          customerId: customerId,
          deliveryFee:
              deliveryFee > 0 ? Money.fromLegacyDoubleTry(deliveryFee) : null,
          orderLevelDiscount: discountAmount > 0
              ? Money.fromLegacyDoubleTry(discountAmount)
              : null,
          customerNote: _buildPreferencesNote(),
        );

    if (!mounted) return;

    await ref
        .read(ordersProvider.notifier)
        .addOrder(OrderModel.fromCanonicalOrder(order));
    if (!mounted) return;
    ref.read(cartProvider.notifier).clearCart();

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (context) => OrderSuccessScreen(orderId: order.id.value),
      ),
      (route) => route.isFirst,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cartItems = ref.watch(cartProvider);
    final addresses = ref.watch(addressesProvider);
    final savedCards = ref.watch(savedCardsProvider);
    final subTotal = ref.watch(cartTotalPriceProvider);
    final restaurantStatus = ref.watch(restaurantStatusProvider);
    final deliveryZoneNotifier = ref.watch(deliveryZoneProvider.notifier);

    if (_selectedAddress == null && addresses.isNotEmpty) {
      _selectedAddress = addresses.first;
    }

    if (_selectedSavedCardId == null && savedCards.isNotEmpty) {
      final defCard = savedCards.firstWhere((c) => c.isDefault,
          orElse: () => savedCards.first);
      _selectedSavedCardId = defCard.id;
    }

    final eligibility = deliveryZoneNotifier.checkEligibility(_selectedAddress);
    final isZoneAvailable = eligibility == 'Teslimat Yapılabilir';
    final isRestaurantAvailable =
        restaurantStatus.isOpen && restaurantStatus.acceptsOrders;

    final zoneInfo = deliveryZoneNotifier.getZoneByAddress(_selectedAddress);
    final double baseDeliveryFee = zoneInfo?.deliveryFee ?? 29.0;
    final double minOrderLimit = zoneInfo?.minimumOrderAmount ?? 0.0;
    final int estimatedMinutes = zoneInfo?.estimatedDeliveryMinutes ??
        restaurantStatus.estimatedDeliveryMinutes;

    final isLimitSatisfied = subTotal >= minOrderLimit;
    final double missingAmount = minOrderLimit - subTotal;

    final effectiveDeliveryFee =
        _appliedCouponCode == 'UCRETSIZ' ? 0.0 : baseDeliveryFee;
    final baseTotal = subTotal + effectiveDeliveryFee;
    final finalDiscount =
        _appliedCouponCode == 'UCRETSIZ' ? 0.0 : _discountAmount;
    final grandTotal = (baseTotal - finalDiscount).clamp(0.0, double.infinity);

    final bool canSubmitOrder =
        (isRestaurantAvailable || _deliveryTimingType == 'scheduled') &&
            isZoneAvailable &&
            isLimitSatisfied &&
            _selectedAddress != null &&
            _selectedPaymentMethod != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Siparişi Tamamla'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (!isRestaurantAvailable && _deliveryTimingType == 'immediate')
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                color: Colors.red.withValues(alpha: 0.1),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: Colors.red),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Restoranımız şu an kapalıdır. Hemen teslimat seçeneği pasiftir. İleri bir tarihe planlayabilirsiniz!',
                        style: AppTypography.bodyMedium.copyWith(
                            color: Colors.red, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            if (isRestaurantAvailable &&
                _selectedAddress != null &&
                !isZoneAvailable)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                color: Colors.red.withValues(alpha: 0.1),
                child: Row(
                  children: [
                    const Icon(Icons.location_off_rounded, color: Colors.red),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Seçilen adres teslimat bölgesi dışındadır veya geçici olarak kapalıdır: ($eligibility)',
                        style: AppTypography.bodyMedium.copyWith(
                            color: Colors.red, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            if (isRestaurantAvailable && isZoneAvailable && !isLimitSatisfied)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                color: Colors.orange.withValues(alpha: 0.1),
                child: Row(
                  children: [
                    const Icon(Icons.shopping_bag_outlined,
                        color: Colors.orange),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Bu bölge için minimum sipariş tutarı ${minOrderLimit.toStringAsFixed(0)} TL\'dir. Sepete ${missingAmount.toStringAsFixed(0)} TL değerinde daha ürün eklemelisiniz.',
                        style: AppTypography.bodyMedium.copyWith(
                            color: Colors.orange, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.xl),
                children: [
                  Text('Teslimat Zamanı',
                      style: AppTypography.titleMedium
                          .copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: AppSpacing.md),
                  AppCard(
                    child: RadioGroup<String>(
                      groupValue: _deliveryTimingType,
                      onChanged: (val) {
                        setState(() {
                          _deliveryTimingType = val!;
                          if (_deliveryTimingType == 'immediate') {
                            _scheduledDeliveryDateTime = null;
                            _timingError = null;
                          }
                        });
                      },
                      child: Column(
                        children: [
                          ListTile(
                            title: const Text(
                                'Hemen (Mümkün olan en kısa sürede)',
                                style: AppTypography.bodyMedium),
                            leading: const Radio<String>(
                              value: 'immediate',
                            ),
                            selected: _deliveryTimingType == 'immediate',
                          ),
                          ListTile(
                            title: const Text(
                                'Tarih/Saat Seç (İleri Zamanlı Planlama)',
                                style: AppTypography.bodyMedium),
                            leading: const Radio<String>(
                              value: 'scheduled',
                            ),
                            selected: _deliveryTimingType == 'scheduled',
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_deliveryTimingType == 'scheduled') ...[
                    const SizedBox(height: AppSpacing.md),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.calendar_month_rounded),
                      onPressed: _pickScheduledDateTime,
                      label: Text(_scheduledDeliveryDateTime == null
                          ? 'Tarih ve Saat Ayarla'
                          : 'Planlanan Zaman: ${_formatDateTime(_scheduledDeliveryDateTime)}'),
                    ),
                    if (_timingError != null) ...[
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xs),
                        child: Text(_timingError!,
                            style: const TextStyle(
                                color: Colors.redAccent,
                                fontSize: 12,
                                fontWeight: FontWeight.w500)),
                      ),
                    ],
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  Text('Teslimat Adresi',
                      style: AppTypography.titleMedium
                          .copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: AppSpacing.md),
                  addresses.isEmpty
                      ? Container(
                          padding: const EdgeInsets.all(AppSpacing.xl),
                          decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: AppRadius.kMedium,
                              border: Border.all(color: AppColors.border)),
                          child: Column(
                            children: [
                              Text('Kayıtlı adresiniz bulunmuyor.',
                                  style: AppTypography.bodyMedium.copyWith(
                                      color: AppColors.textSecondary)),
                              const SizedBox(height: AppSpacing.md),
                              OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (context) =>
                                              const AddressFormScreen()));
                                },
                                icon: const Icon(Icons.add_rounded),
                                label: const Text('Adres Ekle'),
                              ),
                            ],
                          ),
                        )
                      : Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md),
                          decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: AppRadius.kMedium,
                              border: Border.all(color: AppColors.border)),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<AddressModel>(
                              value: addresses.contains(_selectedAddress)
                                  ? _selectedAddress
                                  : addresses.first,
                              isExpanded: true,
                              icon: const Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  color: AppColors.primary),
                              items: addresses.map((AddressModel addr) {
                                return DropdownMenuItem<AddressModel>(
                                    value: addr,
                                    child: Text(
                                        '${addr.title} - ${addr.neighborhood}, ${addr.district}'));
                              }).toList(),
                              onChanged: (AddressModel? newValue) {
                                setState(() {
                                  _selectedAddress = newValue;
                                });
                              },
                            ),
                          ),
                        ),
                  if (_selectedAddress != null &&
                      _deliveryTimingType == 'immediate') ...[
                    const SizedBox(height: AppSpacing.xs),
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                      child: Text(
                          'Tahmini Teslimat Süresi: $estimatedMinutes dk',
                          style: AppTypography.bodySmall.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold)),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  Text('Servis Malzemeleri',
                      style: AppTypography.titleMedium
                          .copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: AppSpacing.md),
                  AppCard(
                    borderColor: _showCutleryError ? Colors.redAccent : null,
                    child: RadioGroup<String>(
                      groupValue: _selectedCutleryPreference,
                      onChanged: (val) {
                        setState(() {
                          _selectedCutleryPreference = val;
                          _showCutleryError = false;
                        });
                      },
                      child: Column(
                        children: [
                          ListTile(
                            title: const Text(
                                'Peçete, çatal ve bıçak istiyorum',
                                style: AppTypography.bodyMedium),
                            leading: const Radio<String>(
                              value: 'want',
                            ),
                            selected: _selectedCutleryPreference == 'want',
                          ),
                          ListTile(
                            title: const Text('Servis malzemesi istemiyorum',
                                style: AppTypography.bodyMedium),
                            leading: const Radio<String>(
                              value: 'dont_want',
                            ),
                            selected: _selectedCutleryPreference == 'dont_want',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text('Ödeme Yöntemi',
                      style: AppTypography.titleMedium
                          .copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: AppSpacing.md),
                  AppCard(
                    child: RadioGroup<String>(
                      groupValue: _selectedPaymentMethod,
                      onChanged: (String? value) {
                        setState(() {
                          _selectedPaymentMethod = value;
                        });
                      },
                      child: Column(
                        children: _paymentMethods.map((method) {
                          final isSelected = _selectedPaymentMethod == method;
                          return Column(
                            children: [
                              ListTile(
                                title: Text(method,
                                    style: AppTypography.bodyMedium),
                                leading: Radio<String>(
                                  value: method,
                                ),
                                selected: isSelected,
                              ),
                              if (method == 'Online Kredi/Banka Kartı' &&
                                  isSelected &&
                                  savedCards.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(
                                      left: AppSpacing.xl,
                                      right: AppSpacing.md,
                                      bottom: AppSpacing.sm),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: AppSpacing.sm),
                                    decoration: const BoxDecoration(
                                      color: AppColors.surfaceVariant,
                                      borderRadius: AppRadius.kSmall,
                                    ),
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<String>(
                                        value: _selectedSavedCardId,
                                        isExpanded: true,
                                        items: savedCards.map((c) {
                                          return DropdownMenuItem<String>(
                                            value: c.id,
                                            child: Text(
                                                '${c.cardBrand} - •••• ${c.lastFourDigits} (${c.cardHolderName})'),
                                          );
                                        }).toList(),
                                        onChanged: (val) {
                                          setState(() {
                                            _selectedSavedCardId = val;
                                          });
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text('Kupon Kodu',
                      style: AppTypography.titleMedium
                          .copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _couponController,
                          enabled: _appliedCouponCode == null,
                          decoration: InputDecoration(
                            hintText: 'Kupon kodunu buraya yazın',
                            errorText: _couponError,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                                vertical: AppSpacing.sm),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      ElevatedButton(
                        onPressed: _appliedCouponCode == null
                            ? () => _applyCoupon(subTotal, baseDeliveryFee)
                            : null,
                        style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.xl,
                                vertical: AppSpacing.md)),
                        child: const Text('Uygula'),
                      ),
                    ],
                  ),
                  if (_appliedCouponCode != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                      decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.08),
                          borderRadius: AppRadius.kSmall,
                          border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.2))),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.confirmation_number_rounded,
                                  color: AppColors.primary, size: 18),
                              const SizedBox(width: AppSpacing.xs),
                              Text('Uygulanan Kupon: $_appliedCouponCode',
                                  style: AppTypography.bodyMedium.copyWith(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                          IconButton(
                              icon: const Icon(Icons.cancel_rounded,
                                  color: AppColors.textSecondary, size: 20),
                              onPressed: _removeCoupon,
                              tooltip: 'Kuponu kaldır',
                              constraints: const BoxConstraints(
                                minWidth: AppThemeConstants.minTapTargetSize,
                                minHeight: AppThemeConstants.minTapTargetSize,
                              ),
                              padding: EdgeInsets.zero),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  Text('Sipariş Tercihleri',
                      style: AppTypography.titleMedium
                          .copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: AppSpacing.md),
                  AppCard(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _noteController,
                          maxLength: 250,
                          maxLines: 2,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText:
                                'Sipariş notu ekleyin (En fazla 250 karakter)',
                            hintStyle: AppTypography.bodyMedium
                                .copyWith(color: AppColors.textSecondary),
                            contentPadding: const EdgeInsets.all(AppSpacing.sm),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        SwitchListTile(
                          title: const Text('Zil çalınsın',
                              style: AppTypography.bodyMedium),
                          value: _ringBell,
                          contentPadding: EdgeInsets.zero,
                          onChanged: (val) => setState(() => _ringBell = val),
                        ),
                        SwitchListTile(
                          title: const Text('Temassız teslimat',
                              style: AppTypography.bodyMedium),
                          value: _contactlessDelivery,
                          contentPadding: EdgeInsets.zero,
                          onChanged: (val) =>
                              setState(() => _contactlessDelivery = val),
                        ),
                        SwitchListTile(
                          title: const Text('Kurye arayabilir',
                              style: AppTypography.bodyMedium),
                          value: _courierCanCall,
                          contentPadding: EdgeInsets.zero,
                          onChanged: (val) =>
                              setState(() => _courierCanCall = val),
                        ),
                        SwitchListTile(
                          title: const Text('Kapıya bırak',
                              style: AppTypography.bodyMedium),
                          value: _leaveAtDoor,
                          contentPadding: EdgeInsets.zero,
                          onChanged: (val) =>
                              setState(() => _leaveAtDoor = val),
                        ),
                        if (_leaveAtDoor) ...[
                          const SizedBox(height: AppSpacing.xs),
                          DropdownButtonFormField<String>(
                            initialValue: _leaveAtDoorLocation,
                            items: _leaveOptions.map((opt) {
                              return DropdownMenuItem<String>(
                                  value: opt, child: Text(opt));
                            }).toList(),
                            onChanged: (val) {
                              setState(() {
                                _leaveAtDoorLocation = val!;
                              });
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text('Sipariş Özeti',
                      style: AppTypography.titleMedium
                          .copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: AppRadius.kMedium,
                        border: Border.all(color: AppColors.border)),
                    child: Column(
                      children: [
                        ...cartItems.map((item) => Padding(
                              padding:
                                  const EdgeInsets.only(bottom: AppSpacing.xs),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('${item.quantity}x ${item.name}',
                                      style: AppTypography.bodyMedium),
                                  Text(
                                      '${item.totalRowPrice.toStringAsFixed(0)} TL',
                                      style: AppTypography.bodyMedium),
                                ],
                              ),
                            )),
                        const Divider(height: AppSpacing.md),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Ara Toplam',
                                style: AppTypography.bodyMedium),
                            Text('${subTotal.toStringAsFixed(0)} TL',
                                style: AppTypography.bodyMedium),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Teslimat Ücreti',
                                style: AppTypography.bodyMedium),
                            Text(
                                effectiveDeliveryFee == 0
                                    ? 'Ücretsiz'
                                    : '${effectiveDeliveryFee.toStringAsFixed(0)} TL',
                                style: AppTypography.bodyMedium.copyWith(
                                    color: effectiveDeliveryFee == 0
                                        ? Colors.green
                                        : null)),
                          ],
                        ),
                        if (_appliedCouponCode != null) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Kupon İndirimi ($_appliedCouponCode)',
                                  style: AppTypography.bodyMedium
                                      .copyWith(color: AppColors.primary)),
                              Text('-${_discountAmount.toStringAsFixed(0)} TL',
                                  style: AppTypography.bodyMedium.copyWith(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ],
                        if (_deliveryTimingType == 'scheduled' &&
                            _scheduledDeliveryDateTime != null) ...[
                          const Divider(height: AppSpacing.md),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Planlanan Teslimat',
                                  style: AppTypography.bodyMedium.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primary)),
                              Text(_formatDateTime(_scheduledDeliveryDateTime),
                                  style: AppTypography.bodyMedium.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primary)),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(AppSpacing.xl),
              decoration: const BoxDecoration(
                  color: AppColors.surface,
                  border: Border(top: BorderSide(color: AppColors.border))),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Genel Toplam',
                          style: AppTypography.titleMedium
                              .copyWith(fontWeight: FontWeight.bold)),
                      Text('${grandTotal.toStringAsFixed(0)} TL',
                          style: AppTypography.titleLarge.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: canSubmitOrder
                          ? () =>
                              _submitOrder(effectiveDeliveryFee, finalDiscount)
                          : null,
                      style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.md)),
                      child: const Text('Siparişi Onayla'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
