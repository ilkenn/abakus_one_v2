import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Resolves a [PaymentMethod.iconAssetPath] to a Flutter [ImageProvider] —
/// mirrors `ProductImageSource`'s exact seam/rationale
/// (`shared/widgets/images/product_image_source.dart`): returning an
/// [ImageProvider] rather than rendering directly is what lets a future
/// SVG-based renderer replace this implementation alone, with
/// [PaymentMethodLogo] never changing (`docs/decisions.md` ADR-012's
/// logo-fallback/SVG-deferral note).
abstract interface class PaymentMethodIconSource {
  ImageProvider resolve(String iconAssetPath);
}

/// Today's only implementation — a plain local-asset lookup. No real brand
/// asset files are supplied this sprint (see `PaymentMethod`'s own doc
/// comment), so every call currently resolves to a path that doesn't
/// exist — [PaymentMethodLogo] handles that via `Image`'s `errorBuilder`,
/// the same graceful-fallback mechanism `ProductImage` already uses for
/// every currently-missing menu photo, not a special case.
class LocalAssetPaymentMethodIconSource implements PaymentMethodIconSource {
  const LocalAssetPaymentMethodIconSource();

  @override
  ImageProvider resolve(String iconAssetPath) => AssetImage(iconAssetPath);
}

final paymentMethodIconSourceProvider = Provider<PaymentMethodIconSource>((ref) {
  return const LocalAssetPaymentMethodIconSource();
});
