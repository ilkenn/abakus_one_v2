import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether `main()`'s Firebase bootstrap ([FirebaseBootstrapService])
/// succeeded — the one place a Firebase-dependent service/provider checks
/// before assuming Firebase is usable, instead of calling a Firebase API
/// speculatively and handling the failure ad hoc.
///
/// `main()` overrides this with the real bootstrap result before `runApp`.
/// The default here (`false`) is deliberately the fail-closed answer, not
/// an unset/throwing placeholder — the same reasoning as
/// `ProductionUnavailableAuthRepository`'s existing fail-closed pattern: an
/// environment that forgets to override this (a test, a future entry
/// point) gets "Firebase is not ready" rather than a crash or a false
/// "ready."
final firebaseReadyProvider = Provider<bool>((ref) => false);
