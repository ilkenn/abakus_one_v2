import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../remote_config/remote_config_provider.dart';
import 'feature_flags_service.dart';
import 'remote_config_feature_flags_service.dart';

/// The application-wide [FeatureFlagsService], backed by
/// [remoteConfigServiceProvider]. Behaves identically to a no-op today
/// only because [remoteConfigServiceProvider] itself still resolves to
/// `NoOpRemoteConfigService` — swapping in a real remote-config vendor
/// later requires no change here or at any call site of
/// [featureFlagsServiceProvider].
final featureFlagsServiceProvider = Provider<FeatureFlagsService>((ref) {
  return RemoteConfigFeatureFlagsService(
    ref.watch(remoteConfigServiceProvider),
  );
});
