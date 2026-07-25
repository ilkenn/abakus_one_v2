import '../../domain/models/deeplink_enums.dart';
import '../../domain/models/deeplink_payload.dart';

class DeepLinkParser {
  /// Custom Scheme (abakusbowl://...) veya HTTPS (https://abakusbowl.com/...) linklerini ayrıştırır.
  DeepLinkPayload parse(String url) {
    try {
      final uri = Uri.parse(url);
      final pathSegments = uri.pathSegments;
      final queryParams = uri.queryParameters;

      // Host veya path segmentine göre eşleştirme lojikleri
      final String target =
          pathSegments.isNotEmpty ? pathSegments.first : uri.host;

      switch (target) {
        case 'home':
          return DeepLinkPayload(
            type: DeepLinkType.home,
            parameters: queryParams,
            rawUrl: url,
          );
        case 'menu':
          return DeepLinkPayload(
            type: DeepLinkType.menu,
            parameters: queryParams,
            rawUrl: url,
          );
        case 'product':
        case 'product-detail':
          return DeepLinkPayload(
            type: DeepLinkType.productDetail,
            parameters: queryParams,
            rawUrl: url,
          );
        case 'campaign':
        case 'campaign-detail':
          return DeepLinkPayload(
            type: DeepLinkType.campaignDetail,
            parameters: queryParams,
            rawUrl: url,
          );
        case 'order':
        case 'order-detail':
          return DeepLinkPayload(
            type: DeepLinkType.orderDetail,
            parameters: queryParams,
            rawUrl: url,
          );
        case 'track':
        case 'order-tracking':
          return DeepLinkPayload(
            type: DeepLinkType.orderTracking,
            parameters: queryParams,
            rawUrl: url,
          );
        case 'notifications':
        case 'notification-center':
          return DeepLinkPayload(
            type: DeepLinkType.notificationCenter,
            parameters: queryParams,
            rawUrl: url,
          );
        case 'profile':
          return DeepLinkPayload(
            type: DeepLinkType.profile,
            parameters: queryParams,
            rawUrl: url,
          );
        default:
          return DeepLinkPayload(
            type: DeepLinkType.unknown,
            parameters: queryParams,
            rawUrl: url,
          );
      }
    } catch (_) {
      return DeepLinkPayload(
        type: DeepLinkType.unknown,
        parameters: const {},
        rawUrl: url,
      );
    }
  }
}
