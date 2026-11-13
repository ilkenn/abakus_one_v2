import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../bootstrap/firebase_ready_provider.dart';
import '../../data/courier_work_repository.dart';
import '../../domain/work/courier_work_models.dart';

/// 2026-11-12 (Faz 3b) — the server-backed courier app's dependency graph
/// ("Kurye Ekranım"). Replaces the old in-memory courier home/delivery
/// screens for a signed-in courier.
final courierWorkRepositoryProvider = Provider<CourierWorkRepository>((ref) {
  return FirestoreCourierWorkRepository();
});

final courierWorkGatewayProvider = Provider<CourierWorkGateway>((ref) {
  if (!ref.watch(firebaseReadyProvider)) {
    return const UnavailableCourierWorkGateway();
  }
  return FirebaseCourierWorkGateway();
});

/// Opens the phone dialer for [phone] — a provider so widget tests can
/// observe the call instead of launching anything.
/// Opens a `tel:` call or a navigation app (ADR-085 stage 4). Replaced in
/// tests to record what would have been opened.
final courierUriLauncherProvider =
    Provider<Future<void> Function(Uri uri)>((ref) {
  return (uri) async {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  };
});

final courierWorkAccountProvider =
    StreamProvider.family<CourierWorkAccount?, String>((ref, uid) {
  return ref.watch(courierWorkRepositoryProvider).watchAccount(uid);
});

typedef CourierWorkScope = ({String uid, String organizationId});

final courierWorkOrdersProvider =
    StreamProvider.family<List<CourierWorkOrder>, CourierWorkScope>(
        (ref, scope) {
  return ref.watch(courierWorkRepositoryProvider).watchAssignedOrders(
      uid: scope.uid, organizationId: scope.organizationId);
});

final courierOwnRequestsProvider =
    StreamProvider.family<List<CourierOwnPoolRequest>, CourierWorkScope>(
        (ref, scope) {
  return ref
      .watch(courierWorkRepositoryProvider)
      .watchOwnRequests(uid: scope.uid, organizationId: scope.organizationId);
});

typedef CourierPoolScope = ({String organizationId, String districtKey});

/// [CourierPoolScope.districtKey] is the courier's districts joined with
/// `,` (a value-equal family key).
final courierPoolPackagesProvider =
    StreamProvider.family<List<CourierPoolPackage>, CourierPoolScope>(
        (ref, scope) {
  final districts = scope.districtKey.isEmpty
      ? const <String>[]
      : scope.districtKey.split(',');
  return ref.watch(courierWorkRepositoryProvider).watchPoolPackages(
      organizationId: scope.organizationId, districtIds: districts);
});
