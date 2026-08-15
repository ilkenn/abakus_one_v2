import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/use_cases/open_table_guest_session_from_qr_scan.dart';
import '../../data/table_guest_session_firestore_client.dart';
import '../../data/table_guest_session_gateway.dart';
import '../../data/technical_identity_provider.dart';
import 'active_table_context_provider.dart'
    show guestSessionIdGeneratorProvider;

/// Table Guest Session backend dependencies — Phase 3. Kept in a separate
/// file from `table_session_dependencies_provider.dart`/
/// `active_table_context_provider.dart`'s existing dev-only, in-memory
/// providers (`openTableSessionProvider`/`createGuestSessionProvider`/
/// `resolveTableQrTokenProvider`) rather than replacing them there — those
/// are deliberately left untouched (see this phase's report on why they
/// still exist), and this file is the new, production, server-
/// authoritative path `QrScannerScreen`/`DineInCheckoutScreen` actually
/// wire onto now.
final technicalIdentityProviderProvider = Provider<TechnicalIdentityProvider>(
  (ref) => const FirebaseTechnicalIdentityProvider(),
);

final tableGuestSessionGatewayProvider = Provider<TableGuestSessionGateway>(
  (ref) => const FirebaseTableGuestSessionGateway(),
);

final tableGuestSessionFirestoreClientProvider =
    Provider<TableGuestSessionFirestoreClient>(
  (ref) => DefaultTableGuestSessionFirestoreClient(),
);

final openTableGuestSessionFromQrScanProvider =
    Provider<OpenTableGuestSessionFromQrScan>((ref) {
  return OpenTableGuestSessionFromQrScan(
    gateway: ref.watch(tableGuestSessionGatewayProvider),
    identityProvider: ref.watch(technicalIdentityProviderProvider),
    guestSessionIdGenerator: ref.watch(guestSessionIdGeneratorProvider),
  );
});
