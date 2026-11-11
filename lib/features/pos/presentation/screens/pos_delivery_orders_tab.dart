import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../data/pos_action_gateway.dart' show PosDeviceContext;
import 'delivery_order_dispatch_screen.dart';
import 'pos_new_takeaway_order_screen.dart';

/// The Masalar grid's "Paket Servis" tab (2026-11-11, product owner: the old
/// combined "Paket / Gel-Al" tab is split). A "Yeni Paket Servis Siparişi"
/// entry into the phone-order screen in delivery mode, above the existing
/// courier dispatch board ([DeliveryOrderDispatchScreen] — delivery orders
/// awaiting a courier, grouped by neighborhood, with single and batch
/// assignment), reused unchanged.
class PosDeliveryOrdersTab extends StatelessWidget {
  const PosDeliveryOrdersTab({super.key, required this.ctx});

  final PosDeviceContext ctx;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
          child: Row(
            children: [
              const Expanded(
                child: Text('Paket Servis Siparişleri',
                    style: AppTypography.titleMedium),
              ),
              ElevatedButton.icon(
                key: const Key('newDeliveryOrderButton'),
                icon: const Icon(Icons.delivery_dining_rounded),
                label: const Text('Yeni Paket Servis Siparişi'),
                onPressed: () => Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => PosNewTakeawayOrderScreen(
                      ctx: ctx,
                      initialMode: PosPhoneOrderMode.delivery,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: DeliveryOrderDispatchScreen(
            organizationId: ctx.organizationId,
            branchId: ctx.branchId,
          ),
        ),
      ],
    );
  }
}
