import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../cart/domain/models/cart_item.dart';
import '../../domain/models/reservation_draft.dart';

const List<String> _reviewMonthNames = [
  'Ocak',
  'Şubat',
  'Mart',
  'Nisan',
  'Mayıs',
  'Haziran',
  'Temmuz',
  'Ağustos',
  'Eylül',
  'Ekim',
  'Kasım',
  'Aralık',
];

/// Step 6 — review + submit. Faz R.2 §12/§13: name fields are editable
/// (no preload source exists anywhere in this app today — confirmed via
/// research; `TakeawayCheckoutScreen` itself leaves the same two fields
/// blank for the identical reason — matching, not inventing, existing
/// precedent), the verified phone number is read-only display only (never
/// an editable field masquerading as canonical), and — critically — the
/// copy never claims the reservation is confirmed yet ("Rezervasyon
/// Talebini Gönder", never "Rezervasyonu Onayla") since restaurant
/// approval is still pending after this call succeeds.
class ReviewStep extends StatelessWidget {
  const ReviewStep({
    super.key,
    required this.draft,
    required this.verifiedPhoneNumber,
    required this.preorderItems,
    required this.firstNameController,
    required this.lastNameController,
    required this.onNameChanged,
  });

  final ReservationDraft draft;
  final String verifiedPhoneNumber;
  final List<CartItem> preorderItems;
  final TextEditingController firstNameController;
  final TextEditingController lastNameController;
  final VoidCallback onNameChanged;

  @override
  Widget build(BuildContext context) {
    final date = draft.date!;
    final time = draft.time!.toLocal();
    final preorderTotal =
        preorderItems.fold<double>(0, (sum, item) => sum + item.totalRowPrice);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('İletişim Bilgileri', style: AppTypography.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        TextFormField(
          controller: firstNameController,
          onChanged: (_) => onNameChanged(),
          decoration: const InputDecoration(labelText: 'Ad'),
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: AppSpacing.sm),
        TextFormField(
          controller: lastNameController,
          onChanged: (_) => onNameChanged(),
          decoration: const InputDecoration(labelText: 'Soyad'),
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: AppSpacing.lg),
        _ReviewCard(
          rows: [
            _ReviewRow(
                icon: Icons.people_alt_rounded,
                label: 'Kişi Sayısı',
                value: '${draft.partySize}'),
            _ReviewRow(
                icon: Icons.deck_rounded,
                label: 'Alan',
                value: draft.area!.displayName),
            _ReviewRow(
              icon: Icons.calendar_today_rounded,
              label: 'Tarih',
              value:
                  '${date.day} ${_reviewMonthNames[date.month - 1]} ${date.year}',
            ),
            _ReviewRow(
              icon: Icons.schedule_rounded,
              label: 'Saat',
              value:
                  '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
            ),
            _ReviewRow(
              icon: Icons.phone_iphone_rounded,
              label: 'Telefon',
              value: verifiedPhoneNumber,
              trailing: const _VerifiedBadge(),
            ),
          ],
        ),
        if (preorderItems.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          const Text('Ön Sipariş', style: AppTypography.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          _ReviewCard(
            rows: [
              for (final item in preorderItems)
                _ReviewRow(
                  icon: Icons.restaurant_rounded,
                  label: '${item.quantity}x ${item.name}',
                  value: '${item.totalRowPrice.toStringAsFixed(0)} TL',
                ),
              _ReviewRow(
                icon: Icons.payments_rounded,
                label: 'Ön Sipariş Toplamı',
                value: '${preorderTotal.toStringAsFixed(0)} TL',
                emphasize: true,
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _VerifiedBadge extends StatelessWidget {
  const _VerifiedBadge();

  @override
  Widget build(BuildContext context) {
    return const Icon(Icons.verified_rounded,
        size: 16, color: AppColors.success);
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.rows});

  final List<_ReviewRow> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.kMedium,
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      child: Column(children: rows),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
    this.emphasize = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary,
                fontWeight: emphasize ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
          Text(
            value,
            style: AppTypography.bodyMedium.copyWith(
              fontWeight: FontWeight.w700,
              color: emphasize ? AppColors.primary : AppColors.textPrimary,
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 4),
            trailing!,
          ],
        ],
      ),
    );
  }
}
