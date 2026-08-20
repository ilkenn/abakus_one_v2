import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/customer_identity_gateway.dart';
import '../../domain/models/customer_identity.dart';

/// P.4.3B — dependency-injection seam for [CustomerIdentityGateway],
/// mirroring `customerPhotoGatewayProvider`'s exact convention (a plain
/// `Provider` returning the real Firebase-backed implementation,
/// overridable in tests).
final customerIdentityGatewayProvider =
    Provider<CustomerIdentityGateway>((ref) {
  return FirebaseCustomerIdentityGateway();
});

/// A live view of the signed-in customer's own canonical identity —
/// `null` for "signed out" (never queries Firestore in that case) as well
/// as "document doesn't exist yet." Mirrors
/// `customerPhotoGalleryProvider`'s exact uid-sourcing/guest-safety shape.
final customerIdentityProvider =
    StreamProvider.autoDispose<CustomerIdentity?>((ref) {
  final uid = ref.watch(authProvider).session?.uid;
  if (uid == null) return Stream.value(null);

  return ref.watch(customerIdentityGatewayProvider).watchOwnIdentity(uid: uid);
});
