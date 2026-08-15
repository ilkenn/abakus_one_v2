import 'package:flutter/material.dart';
import '../../../../shared/widgets/images/editorial_asset_card.dart';

/// One order-mode option (Masada Sipariş, Gel Al, Paket Servis,
/// Rezervasyon). These assets are wide promotional artwork, not plain
/// product photos — the card shows the complete source image at its own
/// 16:10 aspect ratio (`BoxFit.contain`, never cropped/stretched) via
/// [EditorialAssetCard]. Only a short title renders below the artwork —
/// no separate subtitle, since the artwork itself is expected to carry the
/// promotional message; duplicating it in a second line of Flutter text
/// would repeat what the image already says.
class OrderModeCard extends StatelessWidget {
  final String assetPath;
  final IconData icon;
  final String title;
  final double width;
  final VoidCallback onTap;

  static const double aspectRatio = 16 / 10;

  const OrderModeCard({
    super.key,
    required this.assetPath,
    required this.icon,
    required this.title,
    required this.width,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: EditorialAssetCard(
        assetPath: assetPath,
        aspectRatio: aspectRatio,
        title: title,
        placeholderIcon: icon,
        onTap: onTap,
      ),
    );
  }
}
