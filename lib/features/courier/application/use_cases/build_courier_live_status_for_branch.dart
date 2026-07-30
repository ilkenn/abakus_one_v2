import '../../data/courier_repository.dart';
import '../../domain/location/courier_live_status.dart';
import 'build_courier_live_status.dart';

/// Builds a [CourierLiveStatus] for every courier eligible for one branch
/// — Sprint 5B Part 6/9's "manager can observe every active courier."
/// Branch-scoped by construction: reuses `CourierRepository
/// .findByBranchId`'s existing scoping unchanged (Part 11's "manager may
/// view only authorized branches" is satisfied by the caller only ever
/// supplying a branch the acting manager is authorized for — the same
/// convention `CourierDispatchBoardScreen` already relies on).
class BuildCourierLiveStatusForBranch {
  const BuildCourierLiveStatusForBranch({
    required CourierRepository courierRepository,
    required BuildCourierLiveStatus buildCourierLiveStatus,
  })  : _courierRepository = courierRepository,
        _buildCourierLiveStatus = buildCourierLiveStatus;

  final CourierRepository _courierRepository;
  final BuildCourierLiveStatus _buildCourierLiveStatus;

  Future<List<CourierLiveStatus>> call({required String branchId}) async {
    final couriers = await _courierRepository.findByBranchId(branchId);
    final statuses = <CourierLiveStatus>[];
    for (final courier in couriers) {
      statuses.add(await _buildCourierLiveStatus(
        courierId: courier.id,
        branchId: branchId,
      ));
    }
    return statuses;
  }
}
