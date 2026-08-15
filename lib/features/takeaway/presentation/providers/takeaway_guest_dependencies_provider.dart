import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../qr/presentation/providers/table_guest_session_dependencies_provider.dart'
    show technicalIdentityProviderProvider;
import '../../application/use_cases/open_takeaway_guest_session_from_qr.dart';
import '../../data/takeaway_guest_session_gateway.dart';
import '../../data/takeaway_guest_submission_key_store.dart';
import '../../domain/models/takeaway_guest_context.dart';

/// Takeaway Guest Session backend dependencies — Faz D.4. Mirrors
/// `table_guest_session_dependencies_provider.dart`'s exact shape. Reuses
/// [technicalIdentityProviderProvider] from the `qr` feature directly
/// (channel-agnostic, no reason to duplicate it — that file's own doc
/// comment already establishes this precedent for the dine-in side).
final takeawayGuestSessionGatewayProvider =
    Provider<TakeawayGuestSessionGateway>(
  (ref) => const FirebaseTakeawayGuestSessionGateway(),
);

final openTakeawayGuestSessionFromQrProvider =
    Provider<OpenTakeawayGuestSessionFromQr>((ref) {
  return OpenTakeawayGuestSessionFromQr(
    gateway: ref.watch(takeawayGuestSessionGatewayProvider),
    identityProvider: ref.watch(technicalIdentityProviderProvider),
  );
});

final takeawayGuestSubmissionKeyStoreProvider =
    Provider<TakeawayGuestSubmissionKeyStore>(
  (ref) => const SharedPreferencesTakeawayGuestSubmissionKeyStore(),
);

/// The customer app's "current takeaway QR guest session" state — `null`
/// until a QR token resolves and a session is opened. Mirrors
/// `activeTableContextProvider`'s exact shape (a plain `Notifier<T?>`
/// singleton, not a `.family`/scoped provider — app-wide state that must
/// survive navigation across Menu → Cart → Checkout).
class TakeawayGuestContextNotifier extends Notifier<TakeawayGuestContext?> {
  @override
  TakeawayGuestContext? build() => null;

  void set(TakeawayGuestContext context) {
    state = context;
  }

  void clear() {
    state = null;
  }
}

final takeawayGuestContextProvider =
    NotifierProvider<TakeawayGuestContextNotifier, TakeawayGuestContext?>(() {
  return TakeawayGuestContextNotifier();
});
