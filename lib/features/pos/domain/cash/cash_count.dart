import '../../../../shared/models/money.dart';
import 'cash_declaration.dart';
import 'cash_variance.dart';

/// One immutable cash-counting attempt for a [CashSession] — **never
/// overwritten**; a recount always produces a brand-new [CashCount] with
/// its own [id], never edits a previous one (`CashCountRepository` has no
/// update method at all, enforcing this structurally).
///
/// [expectedAmount] is computed once, at submission time, as the sum of
/// every `CashMovement` recorded for the session so far — frozen here so
/// a later movement can never retroactively change what an already-
/// submitted count's expected figure was.
class CashCount {
  const CashCount({
    required this.id,
    required this.sessionId,
    required this.expectedAmount,
    required this.declaration,
    required this.variance,
    required this.declaredByStaffId,
    required this.declaredAt,
  });

  final String id;
  final String sessionId;
  final Money expectedAmount;
  final CashDeclaration declaration;
  final CashVariance variance;
  final String declaredByStaffId;
  final DateTime declaredAt;
}
