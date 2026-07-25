import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/app_radius.dart';
import '../../domain/models/order_model.dart';
import '../providers/orders_provider.dart';

class OrderDetailScreen extends ConsumerStatefulWidget {
  final OrderModel order;

  const OrderDetailScreen({super.key, required this.order});

  @override
  ConsumerState<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends ConsumerState<OrderDetailScreen> {
  String? _selectedReason;
  final TextEditingController _customReasonController = TextEditingController();

  // Değerlendirme State'leri
  int _overallRating = 0;
  int _tasteRating = 0;
  int _packagingRating = 0;
  int _deliveryRating = 0;
  final TextEditingController _commentController = TextEditingController();

  // Kurye Değerlendirme State'leri
  int _courierRating = 0;
  bool? _courierWasPolite;
  bool? _courierWasOnTime;
  bool? _courierCommunicationWasGood;
  bool? _packageWasHandledCarefully;
  final TextEditingController _courierCommentController =
      TextEditingController();

  final List<String> _cancellationReasons = const [
    'Yanlış ürün seçtim',
    'Adres yanlış',
    'Teslimat süresi uzun',
    'Fikrimi değiştirdim',
    'Diğer',
  ];

  @override
  void dispose() {
    _customReasonController.dispose();
    _commentController.dispose();
    _courierCommentController.dispose();
    super.dispose();
  }

  void _showCancelDialog(BuildContext context, OrderModel currentOrder) {
    _selectedReason = _cancellationReasons.first;
    _customReasonController.clear();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Siparişi İptal Et'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Lütfen iptal etme nedeninizi seçiniz:'),
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<String>(
                  initialValue: _selectedReason,
                  items: _cancellationReasons
                      .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                      .toList(),
                  onChanged: (val) {
                    setDialogState(() {
                      _selectedReason = val;
                    });
                  },
                ),
                if (_selectedReason == 'Diğer') ...[
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _customReasonController,
                    decoration: const InputDecoration(
                      hintText: 'Lütfen iptal açıklamasını buraya yazınız...',
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Vazgeç'),
            ),
            ElevatedButton(
              onPressed: () {
                if (_selectedReason == 'Diğer' &&
                    _customReasonController.text.trim().isEmpty) {
                  return;
                }
                final finalDesc = _selectedReason == 'Diğer'
                    ? _customReasonController.text.trim()
                    : '';
                ref
                    .read(ordersProvider.notifier)
                    .cancelOrder(currentOrder.id, _selectedReason!, finalDesc);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Siparişiniz başarıyla iptal edilmiştir.'),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Siparişi İptal Et'),
            ),
          ],
        ),
      ),
    );
  }

  void _submitReviewForm(String orderId) {
    if (_overallRating == 0 ||
        _tasteRating == 0 ||
        _packagingRating == 0 ||
        _deliveryRating == 0 ||
        _courierRating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Lütfen tüm yıldızlı değerlendirme puanlarını seçiniz!',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (_courierWasPolite == null ||
        _courierWasOnTime == null ||
        _courierCommunicationWasGood == null ||
        _packageWasHandledCarefully == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Lütfen kısa kurye anketi sorularının tamamını cevaplayınız!',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final updatedModel = OrderModel(
      id: orderId,
      date: '',
      totalAmount: 0,
      status: '',
      overallRating: _overallRating,
      tasteRating: _tasteRating,
      packagingRating: _packagingRating,
      deliveryRating: _deliveryRating,
      reviewComment: _commentController.text.trim(),
      courierRating: _courierRating,
      courierWasPolite: _courierWasPolite,
      courierWasOnTime: _courierWasOnTime,
      courierCommunicationWasGood: _courierCommunicationWasGood,
      packageWasHandledCarefully: _packageWasHandledCarefully,
      courierReviewComment: _courierCommentController.text.trim(),
    );

    ref.read(ordersProvider.notifier).submitReview(orderId, updatedModel);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Değerlendirmeniz başarıyla gönderilmiştir. Teşekkür ederiz!',
        ),
      ),
    );
  }

  Widget _buildStarRow(
    String label,
    int currentRating,
    ValueChanged<int> onRatingChanged,
    bool readOnly,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTypography.bodyMedium),
          Row(
            children: List.generate(5, (index) {
              final starValue = index + 1;
              return GestureDetector(
                onTap: readOnly ? null : () => onRatingChanged(starValue),
                child: Icon(
                  starValue <= currentRating
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  color: starValue <= currentRating
                      ? Colors.amber
                      : AppColors.textSecondary,
                  size: 26,
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildYesNoQuestion(
    String question,
    bool? currentValue,
    ValueChanged<bool> onSelected,
    bool readOnly,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(question, style: AppTypography.bodyMedium)),
          Row(
            children: [
              ChoiceChip(
                label: const Text('Evet'),
                selected: currentValue == true,
                onSelected: readOnly
                    ? null
                    : (selected) {
                        if (selected) onSelected(true);
                      },
              ),
              const SizedBox(width: AppSpacing.xs),
              ChoiceChip(
                label: const Text('Hayır'),
                selected: currentValue == false,
                onSelected: readOnly
                    ? null
                    : (selected) {
                        if (selected) onSelected(false);
                      },
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final freshOrders = ref.watch(ordersProvider);
    final freshOrder = freshOrders.firstWhere(
      (o) => o.id == widget.order.id,
      orElse: () => widget.order,
    );

    final isScheduled = freshOrder.deliveryTimingType == 'scheduled';
    final isCancelled = freshOrder.status == 'İptal Edildi';
    final isDelivered = freshOrder.status == 'Teslim Edildi';
    final isReviewed = freshOrder.overallRating != null;

    final bool canCancel = freshOrder.status == 'Onay Bekliyor' ||
        freshOrder.status == 'Bekliyor' ||
        freshOrder.status == 'Onaylandı';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sipariş Detayı'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.xl),
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: isCancelled
                          ? AppColors.surfaceVariant.withValues(alpha: 0.4)
                          : AppColors.surface,
                      borderRadius: AppRadius.kMedium,
                      border: Border.all(
                        color: isCancelled
                            ? Colors.red.withValues(alpha: 0.2)
                            : AppColors.border,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Sipariş: ${freshOrder.id}',
                              style: AppTypography.titleMedium.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              freshOrder.status,
                              style: TextStyle(
                                color: isCancelled
                                    ? Colors.red
                                    : (freshOrder.status == 'Hazırlanıyor'
                                        ? Colors.orange
                                        : Colors.green),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Tarih: ${freshOrder.date}',
                          style: AppTypography.bodyMedium.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        Text(
                          'Tutar: ${freshOrder.totalAmount.toStringAsFixed(0)} TL',
                          style: AppTypography.bodyLarge.copyWith(
                            fontWeight: FontWeight.bold,
                            color: isCancelled
                                ? AppColors.textSecondary
                                : AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isCancelled) ...[
                    const SizedBox(height: AppSpacing.md),
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.05),
                        borderRadius: AppRadius.kMedium,
                        border: Border.all(
                          color: Colors.red.withValues(alpha: 0.15),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'İptal Bilgileri',
                            style: AppTypography.bodyLarge.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'İptal Zamanı: ${freshOrder.cancelledAt ?? ''}',
                            style: AppTypography.bodyMedium,
                          ),
                          Text(
                            'Nedeni: ${freshOrder.cancellationReason ?? ''}',
                            style: AppTypography.bodyMedium,
                          ),
                          if (freshOrder.cancellationDescription != null &&
                              freshOrder.cancellationDescription!.isNotEmpty)
                            Text(
                              'Açıklama: ${freshOrder.cancellationDescription}',
                              style: AppTypography.bodyMedium,
                            ),
                        ],
                      ),
                    ),
                  ],
                  if (isDelivered) ...[
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      isReviewed
                          ? 'Sipariş Değerlendirmeniz'
                          : 'Siparişi Değerlendir',
                      style: AppTypography.titleMedium.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: AppRadius.kMedium,
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildStarRow(
                            'Genel Puan',
                            isReviewed
                                ? freshOrder.overallRating!
                                : _overallRating,
                            (v) => setState(() => _overallRating = v),
                            isReviewed,
                          ),
                          _buildStarRow(
                            'Lezzet Puanı',
                            isReviewed ? freshOrder.tasteRating! : _tasteRating,
                            (v) => setState(() => _tasteRating = v),
                            isReviewed,
                          ),
                          _buildStarRow(
                            'Paketleme Puanı',
                            isReviewed
                                ? freshOrder.packagingRating!
                                : _packagingRating,
                            (v) => setState(() => _packagingRating = v),
                            isReviewed,
                          ),
                          _buildStarRow(
                            'Teslimat Puanı',
                            isReviewed
                                ? freshOrder.deliveryRating!
                                : _deliveryRating,
                            (v) => setState(() => _deliveryRating = v),
                            isReviewed,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          if (isReviewed) ...[
                            if (freshOrder.reviewComment != null &&
                                freshOrder.reviewComment!.isNotEmpty) ...[
                              Text(
                                'Yorumunuz:',
                                style: AppTypography.bodySmall.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                freshOrder.reviewComment!,
                                style: AppTypography.bodyMedium.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ] else ...[
                            TextField(
                              controller: _commentController,
                              maxLength: 500,
                              maxLines: 2,
                              onChanged: (_) => setState(() {}),
                              decoration: const InputDecoration(
                                hintText:
                                    'Siparişle ilgili yorumunuz (En fazla 500 karakter)',
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      isReviewed
                          ? 'Kurye Değerlendirmeniz'
                          : 'Kurye Değerlendirmesi',
                      style: AppTypography.titleMedium.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: AppRadius.kMedium,
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildStarRow(
                            'Kurye Puanı',
                            isReviewed
                                ? freshOrder.courierRating!
                                : _courierRating,
                            (v) => setState(() => _courierRating = v),
                            isReviewed,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          _buildYesNoQuestion(
                            'Kurye nazik miydi?',
                            isReviewed
                                ? freshOrder.courierWasPolite
                                : _courierWasPolite,
                            (v) => setState(() => _courierWasPolite = v),
                            isReviewed,
                          ),
                          _buildYesNoQuestion(
                            'Sipariş zamanında ulaştı mı?',
                            isReviewed
                                ? freshOrder.courierWasOnTime
                                : _courierWasOnTime,
                            (v) => setState(() => _courierWasOnTime = v),
                            isReviewed,
                          ),
                          _buildYesNoQuestion(
                            'Teslimat sırasında iletişim yeterli miydi?',
                            isReviewed
                                ? freshOrder.courierCommunicationWasGood
                                : _courierCommunicationWasGood,
                            (v) => setState(
                              () => _courierCommunicationWasGood = v,
                            ),
                            isReviewed,
                          ),
                          _buildYesNoQuestion(
                            'Paket dikkatli taşınmış mıydı?',
                            isReviewed
                                ? freshOrder.packageWasHandledCarefully
                                : _packageWasHandledCarefully,
                            (v) =>
                                setState(() => _packageWasHandledCarefully = v),
                            isReviewed,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          if (isReviewed) ...[
                            if (freshOrder.courierReviewComment != null &&
                                freshOrder
                                    .courierReviewComment!.isNotEmpty) ...[
                              Text(
                                'Kurye Yorumunuz:',
                                style: AppTypography.bodySmall.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                freshOrder.courierReviewComment!,
                                style: AppTypography.bodyMedium.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ] else ...[
                            TextField(
                              controller: _courierCommentController,
                              maxLength: 300,
                              maxLines: 2,
                              onChanged: (_) => setState(() {}),
                              decoration: const InputDecoration(
                                hintText:
                                    'Kurye ile ilgili ek yorumunuz (En fazla 300 karakter)',
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (!isReviewed) ...[
                      const SizedBox(height: AppSpacing.xl),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => _submitReviewForm(freshOrder.id),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.md,
                            ),
                          ),
                          child: const Text('Değerlendirmeyi Gönder'),
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    'Sipariş ve Teslimat Tercihleri',
                    style: AppTypography.titleMedium.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: AppRadius.kMedium,
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildPreferenceRow(
                          Icons.timer_outlined,
                          'Teslimat Türü:',
                          isScheduled
                              ? 'Planlı Teslimat'
                              : 'Mümkün Olan En Kısa Sürede',
                        ),
                        if (isScheduled &&
                            freshOrder.scheduledDeliveryDateTime.isNotEmpty &&
                            !isCancelled)
                          _buildPreferenceRow(
                            Icons.calendar_month_rounded,
                            'Planlanan Zaman:',
                            freshOrder.scheduledDeliveryDateTime,
                          ),
                        _buildPreferenceRow(
                          Icons.restaurant_rounded,
                          'Servis Malzemesi:',
                          freshOrder.serviceMaterialsPreference.isNotEmpty
                              ? freshOrder.serviceMaterialsPreference
                              : 'Belirtilmedi',
                        ),
                        _buildPreferenceRow(
                          Icons.notifications_rounded,
                          'Zil Durumu:',
                          freshOrder.ringBell
                              ? 'Zil Çalınsın'
                              : 'Zil Çalınmasın',
                        ),
                        _buildPreferenceRow(
                          Icons.sensor_door_rounded,
                          'Kapıya Bırak:',
                          freshOrder.leaveAtDoor
                              ? 'Evet (${freshOrder.leaveAtDoorLocation})'
                              : 'Hayır',
                        ),
                        if (freshOrder.customDeliveryInstruction.isNotEmpty)
                          _buildPreferenceRow(
                            Icons.edit_note_rounded,
                            'Teslimat Notu:',
                            freshOrder.customDeliveryInstruction,
                          ),
                        _buildPreferenceRow(
                          Icons.gpp_good_rounded,
                          'Temassız Teslimat:',
                          freshOrder.contactlessDelivery ? 'Evet' : 'Hayır',
                        ),
                        _buildPreferenceRow(
                          Icons.phone_enabled_rounded,
                          'Kurye Arama İzni:',
                          freshOrder.courierCanCall ? 'Arayabilir' : 'Aramasın',
                        ),
                        if (freshOrder.orderNote.isNotEmpty) ...[
                          const Divider(height: AppSpacing.lg),
                          Text(
                            'Müşteri Notu:',
                            style: AppTypography.bodySmall.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            freshOrder.orderNote,
                            style: AppTypography.bodyMedium.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (canCancel)
              Container(
                padding: const EdgeInsets.all(AppSpacing.xl),
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => _showCancelDialog(context, freshOrder),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.md,
                      ),
                    ),
                    child: const Text('Siparişi İptal Et'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreferenceRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: AppSpacing.sm),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
