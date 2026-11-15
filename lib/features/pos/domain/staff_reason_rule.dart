/// ADR-085 stage 6C-2 — the shortest written reason accepted for any staff
/// cancellation, comp/discount or cash count difference. The server
/// enforces the same rule (`functions/src/managerOversight.ts`
/// `requireStaffReason`); this copy only gives the user early feedback.
const int minStaffReasonLength = 5;

/// Validator text for a staff reason field, or `null` when it is long enough.
String? staffReasonError(String? value) =>
    (value ?? '').trim().length < minStaffReasonLength
        ? 'En az $minStaffReasonLength karakterlik bir açıklama yazın.'
        : null;
