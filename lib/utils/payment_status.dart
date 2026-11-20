// FILE: utils/payment_status.dart
// Payment statuses the app understands: unpaid · partial · in_progress · paid (full) · refunded.
// "Partial" (only part of the money is in) and "in progress" (completed, remaining amount not settled yet)
// are both shown as "Payment In Progress" in the Bookings list and on the Dashboard.

class PaymentStatusX {
  PaymentStatusX._();

  static String _norm(String? s) => (s ?? '').trim().toLowerCase().replaceAll(RegExp(r'[\s\-]+'), '_');

  /// True for `partial` / `in_progress` (and close spellings of them).
  static bool isInProgress(String? s) {
    const keys = {'partial', 'partially_paid', 'partial_paid', 'part_paid', 'in_progress', 'payment_in_progress', 'processing'};
    return keys.contains(_norm(s));
  }

  static bool isFull(String? s) => const {'paid', 'full', 'fully_paid'}.contains(_norm(s));

  /// Readable text for a raw server value (`in_progress` → `Payment In Progress`).
  static String? label(String? s) {
    final n = _norm(s);
    if (n.isEmpty) return null;
    if (isInProgress(s)) return n.startsWith('part') ? 'Partly Paid' : 'Payment In Progress';
    if (isFull(s)) return 'Paid';
    return n[0].toUpperCase() + n.substring(1).replaceAll('_', ' ');
  }
}