import 'deeplink_enums.dart';

class DeepLinkPayload {
  final DeepLinkType type;
  final Map<String, String> parameters;
  final String rawUrl;

  const DeepLinkPayload({
    required this.type,
    required this.parameters,
    required this.rawUrl,
  });
}
