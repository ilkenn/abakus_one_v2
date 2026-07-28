import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_radius.dart';
import 'payment_method_icon_source.dart';

/// Renders a [PaymentMethod]'s brand logo by [iconAssetPath], resolved
/// through [paymentMethodIconSourceProvider] — mirrors `ProductImage`'s
/// exact fallback pattern: never asks where the image actually comes from
/// (a local asset today; a CDN/SVG-renderer-backed source later without
/// this widget changing at all), and falls back to a
/// [brandColorValue]-tinted icon instead of a broken image when no real
/// asset exists for that path (true for every seed method this sprint —
/// see `docs/decisions.md` ADR-012).
class PaymentMethodLogo extends ConsumerWidget {
  const PaymentMethodLogo({
    super.key,
    required this.iconAssetPath,
    required this.brandColorValue,
    this.size = 40,
  });

  final String iconAssetPath;
  final int brandColorValue;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(paymentMethodIconSourceProvider);
    final provider = source.resolve(iconAssetPath);
    final brandColor = Color(brandColorValue);

    return ClipRRect(
      borderRadius: AppRadius.kSmall,
      child: SizedBox(
        width: size,
        height: size,
        child: Image(
          image: provider,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _placeholder(brandColor),
        ),
      ),
    );
  }

  Widget _placeholder(Color brandColor) {
    return Container(
      color: brandColor.withValues(alpha: 0.12),
      child: Icon(Icons.payments_outlined, color: brandColor, size: size * 0.55),
    );
  }
}
