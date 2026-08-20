import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/current_organization.dart';
import '../../../../core/services/logging/logging_provider.dart';
import '../../../../shared/models/customer_photo.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/customer_photo_gateway.dart';
import '../../data/customer_photo_picker.dart';
import '../../data/customer_photo_storage_client.dart';

/// Profile P.4.3A — dependency-injection seam for the customer photo
/// gallery/upload feature. Mirrors this codebase's existing gateway-
/// provider convention (e.g. `checkDeliveryEligibilityGatewayProvider`) —
/// a plain `Provider` returning the real implementation, overridable in
/// tests.
final customerPhotoGatewayProvider = Provider<CustomerPhotoGateway>((ref) {
  return FirebaseCustomerPhotoGateway(
    loggingService: ref.watch(loggingServiceProvider),
  );
});

final customerPhotoStorageClientProvider =
    Provider<CustomerPhotoStorageClient>((ref) {
  return FirebaseCustomerPhotoStorageClient(
    loggingService: ref.watch(loggingServiceProvider),
  );
});

final customerPhotoPickerProvider = Provider<CustomerPhotoPicker>((ref) {
  return const ImagePickerCustomerPhotoPicker();
});

/// The tenant this customer's photo gallery/uploads are scoped to.
/// Reuses `core/config/current_organization.dart`'s single-tenant
/// constant directly — deliberately NOT `features/admin`'s own
/// `currentOrganizationIdProvider` (`admin_dependencies_provider.dart`),
/// which would violate "do not import Admin presentation code into
/// this feature." Both currently resolve to the same literal; this is the
/// architecturally correct source, not a coincidence-dependent shortcut.
final currentCustomerOrganizationIdProvider = Provider<String>((ref) {
  return kSingleTenantOrganizationId;
});

/// A live view of the signed-in customer's own private gallery — `null`
/// (via `AsyncValue.data(const [])`) is never returned for "signed out";
/// signed-out/guest simply never watches this in practice (the entry
/// point that would trigger it is itself authenticated-only), but this
/// provider still fails safe (an empty, static stream) rather than
/// crashing if it ever is.
///
/// CR.1.2 — sources `customerId` from `authProvider`'s own session uid
/// directly, never `features/profile`'s `profileProvider` (this module is
/// now shared between `features/profile` and `features/customer_registration`,
/// so it cannot reach into either feature's own presentation layer —
/// `profileProvider` itself only ever derived this same uid from
/// `authProvider` in the first place, so this is a same-value swap, not a
/// behavior change).
final customerPhotoGalleryProvider =
    StreamProvider.autoDispose<List<CustomerPhoto>>((ref) {
  final customerId = ref.watch(authProvider).session?.uid;
  if (customerId == null) return Stream.value(const <CustomerPhoto>[]);

  final organizationId = ref.watch(currentCustomerOrganizationIdProvider);
  return ref
      .watch(customerPhotoGatewayProvider)
      .watchGallery(organizationId: organizationId, customerId: customerId);
});

/// P.4.3B — a live view of the customer's own canonical PUBLIC photo
/// selection (`customerPublicProfiles/{organizationId}_{uid}.selectedProfilePhotoRef`),
/// `null` for "no selection yet" as well as "signed out" — mirrors
/// `customerPhotoGalleryProvider`'s exact uid/organizationId-sourcing and
/// guest-safety shape. This is the ONE source `resolveCustomerHeroPhoto`
/// (`customer_photo_client_rules.dart`) treats as authoritative for
/// "approved + selected" — never `CustomerPhoto.isSelectedAsProfilePhoto`
/// alone.
final customerSelectedProfilePhotoRefProvider =
    StreamProvider.autoDispose<String?>((ref) {
  final customerId = ref.watch(authProvider).session?.uid;
  if (customerId == null) return Stream.value(null);

  final organizationId = ref.watch(currentCustomerOrganizationIdProvider);
  return ref.watch(customerPhotoGatewayProvider).watchSelectedProfilePhotoRef(
        organizationId: organizationId,
        customerId: customerId,
      );
});

/// Fetches (and caches, per `photoRef`) the raw bytes of one private
/// gallery photo for rendering — `Reference.getData()`, never a public
/// download URL (see `CustomerPhotoStorageClient`'s own doc comment).
/// `.family` + `.autoDispose` — bytes are only kept around while a tile
/// actually watching this specific `photoRef` is on screen.
final customerPhotoBytesProvider =
    FutureProvider.autoDispose.family<Uint8List?, String>((ref, photoRef) {
  return ref.watch(customerPhotoStorageClientProvider).downloadBytes(photoRef);
});
