import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/saved_address_repository.dart';
import '../../domain/models/saved_address.dart';

/// Faz P.2.1.1 — the real wiring [SavedAddressRepository] was missing
/// entirely: `address_details_form_screen.dart` originally declared this
/// provider as an unconditional `throw UnimplementedError(...)`
/// placeholder, and nothing anywhere in `lib/bootstrap/app_bootstrap.dart`
/// (or any other provider-override list) ever overrode it — meaning the
/// canonical save path would have crashed immediately on first real use,
/// entirely independent of the navigation bug this phase also fixes. See
/// `docs/decisions.md` Faz P.2.1.1 for the full audit.
///
/// [FirestoreSavedAddressRepository.currentUid] is a closure (not a
/// snapshot value) so it always reads whichever session is live *at save
/// time*, never a uid captured once at provider-construction time —
/// matches [FirestoreSavedAddressRepository]'s own existing constructor
/// shape (P.2), unmodified here.
final savedAddressRepositoryProvider = Provider<SavedAddressRepository>((ref) {
  return FirestoreSavedAddressRepository(
    currentUid: () {
      final uid = ref.read(authProvider).session?.uid;
      if (uid == null) {
        throw StateError(
          'savedAddressRepositoryProvider requires an authenticated '
          'session — no anonymous/guest delivery-address saving exists.',
        );
      }
      return uid;
    },
  );
});

/// Faz P.2.1.2 — the customer-visible saved-address list, backed by the
/// canonical `customerAddresses` Firestore collection (via
/// [savedAddressRepositoryProvider]), not the legacy in-memory
/// `addressesProvider`/`AddressModel`. [SavedAddressRepository] has no
/// `watch`/stream method (P.2 never added one), so per the smallest-
/// architecture-consistent-with-the-existing-pattern instruction, this is
/// an explicit-refresh `AsyncNotifier`, not a live Firestore listener —
/// [refresh] is called by the UI after returning from the create/edit
/// flow, not on every write automatically.
class SavedAddressListNotifier extends AsyncNotifier<List<SavedAddress>> {
  @override
  Future<List<SavedAddress>> build() {
    return ref.read(savedAddressRepositoryProvider).listForCurrentUser();
  }

  Future<void> refresh() async {
    state = const AsyncLoading<List<SavedAddress>>().copyWithPrevious(state);
    state = await AsyncValue.guard(
      () => ref.read(savedAddressRepositoryProvider).listForCurrentUser(),
    );
  }
}

final savedAddressListProvider =
    AsyncNotifierProvider<SavedAddressListNotifier, List<SavedAddress>>(
  SavedAddressListNotifier.new,
);
