import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_environment_config.dart';

/// The [AppEnvironmentConfig] for [AppEnvironmentConfig.current] —
/// exposed as a provider (rather than callers reading the static getter
/// directly) so tests can override it with a specific environment without
/// depending on the `ENVIRONMENT` compile-time define.
final appEnvironmentConfigProvider = Provider<AppEnvironmentConfig>((ref) {
  return AppEnvironmentConfig.current;
});
