/// Who performed a mutating action against an order.
///
/// Shared between [OrderCancellationInfo] and [OrderAuditEntry] on purpose —
/// "who cancelled this" and "who made this audited change" are the same
/// question, and modeling them as two separate enums with identical values
/// would be exactly the kind of duplicate concept this codebase's
/// conventions rule out.
enum OrderActor { customer, staff, kitchen, system }
