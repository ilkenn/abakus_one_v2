import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'noop_remote_config_service.dart';
import 'remote_config_service.dart';

final remoteConfigServiceProvider = Provider<RemoteConfigService>((ref) {
  return const NoOpRemoteConfigService();
});
