/// A staff-authored note on a CRM `Customer` — Phase 6F
/// (`docs/decisions.md` ADR-023). Doubles as the "risk/review flags
/// foundation" the brief asks for via [isFlag], rather than building a
/// second, parallel flagging system: a flagged note is simply a note
/// with [isFlag] set. Immutable, append-only — mirrors every other
/// audit-adjacent trail in this codebase (no update/delete method on
/// `CustomerAdminNoteRepository`).
class CustomerAdminNote {
  const CustomerAdminNote({
    required this.id,
    required this.customerId,
    required this.authorStaffId,
    required this.body,
    this.isFlag = false,
    required this.createdAt,
  });

  final String id;
  final String customerId;
  final String authorStaffId;
  final String body;
  final bool isFlag;
  final DateTime createdAt;
}
