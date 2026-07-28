import '../../../orders/domain/models/order_id.dart';
import 'kitchen_ticket_header.dart';
import 'kitchen_ticket_line.dart';
import 'kitchen_ticket_type.dart';

/// One kitchen-facing ticket derived from an [Order] — the domain shape
/// behind both the main kitchen screen (KDS, Phase 3 Sprint 3D Phase 8)
/// and any future printed output. **Domain/contract only this sprint** —
/// no printer hardware integration exists (`KitchenTicketPrintProvider`
/// is the seam a real integration would sit behind).
///
/// [lines] appear here in full — station-based routing infrastructure may
/// exist elsewhere, but every product (including drinks, hot, and cold
/// items) is included on this single ticket by default for Abaküs, per
/// the explicit requirement that station separation stay disabled.
///
/// **Append-only**: never mutated in place — every change (a line marked
/// ready, the order marked ready) produces a new instance with the same
/// [id] and an incremented [revision]; `KitchenTicketRepository.save`
/// always appends.
class KitchenTicket {
  const KitchenTicket({
    required this.id,
    required this.orderId,
    required this.branchId,
    required this.type,
    required this.header,
    required this.lines,
    this.isCopy = false,
    required this.firedAt,
    this.completedLineIds = const [],
    this.orderReadyAt,
    required this.revision,
  });

  /// Externally supplied by `KitchenTicketIdGenerator` — never a business
  /// identity, matching every other ticket/session/split id in this
  /// codebase.
  final String id;

  final OrderId orderId;
  final String branchId;

  final KitchenTicketType type;
  final KitchenTicketHeader header;
  final List<KitchenTicketLine> lines;

  /// Whether this print is a reprint/duplicate of an earlier ticket —
  /// must be marked clearly as COPY wherever rendered. Independent of
  /// [type] (a delta ticket can itself be reprinted).
  final bool isCopy;

  final DateTime firedAt;

  /// Ids of [lines] marked ready by kitchen staff — the product-level
  /// completion tracking the KDS/expeditor phases (Phase 8/9) read.
  final List<String> completedLineIds;

  /// Set once every line is marked ready — `null` until then. The
  /// expeditor's "how long has this been ready" reading is
  /// `now - orderReadyAt`.
  final DateTime? orderReadyAt;

  /// Optimistic-concurrency counter — starts at 1.
  final int revision;

  bool get isFullyReady => lines.every((l) => completedLineIds.contains(l.id));

  KitchenTicket copyWith({
    bool? isCopy,
    List<String>? completedLineIds,
    DateTime? orderReadyAt,
    int? revision,
  }) {
    return KitchenTicket(
      id: id,
      orderId: orderId,
      branchId: branchId,
      type: type,
      header: header,
      lines: lines,
      isCopy: isCopy ?? this.isCopy,
      firedAt: firedAt,
      completedLineIds: completedLineIds ?? this.completedLineIds,
      orderReadyAt: orderReadyAt ?? this.orderReadyAt,
      revision: revision ?? this.revision,
    );
  }
}
