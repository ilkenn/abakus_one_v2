import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'clock.dart';

/// The [Clock] currently in use — [SystemClock] today. Mirrors every
/// other service-seam provider in this codebase (`loggingServiceProvider`,
/// `remoteConfigServiceProvider`, ...): nothing that depends on [Clock]
/// ever depends on [SystemClock] directly, so tests can override this one
/// provider with a fake instead.
final clockProvider = Provider<Clock>((ref) => const SystemClock());
