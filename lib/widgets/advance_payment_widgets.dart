// FILE: widgets/advance_payment_widgets.dart
// Advance (20%) bookings: the "Did you receive ₹… ?" Yes / No question and the payment summary card.
// Amounts always come from the server (paymentSummary) — the app never works out 20% itself.

import 'package:flutter/material.dart';

import '../models/booking/booking.dart';
import '../theme/tokens.dart';
import 'common.dart';

String _rs(double v) => '₹${v.toStringAsFixed(v % 1 == 0 ? 0 : 2)}';

/// Bottom sheet: "Did you receive ₹1200 from the customer?" → true (Yes) / false (No) / null (closed without answering).
Future<bool?> askBalanceReceived(BuildContext context, PaymentSummary summary) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AiraColors.card,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Did You Receive ${_rs(summary.balanceDue)} From The Customer?',
                style: AiraText.serif(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              'The Customer Already Paid ${_rs(summary.paidAmount)} Online. The Rest Is Paid To You After The Service. '
                  'If You Have Not Been Paid Yet, Choose No — You Can Still Answer Yes Later.',
              style: AiraText.sans(fontSize: 13, color: AiraColors.charcoalSoft, height: 1.4),
            ),
            const SizedBox(height: 18),
            PrimaryButton(label: 'Yes, I Received It', expand: true, onTap: () => Navigator.pop(ctx, true)),
            const SizedBox(height: 10),
            GhostButton(label: 'No, Not Received', expand: true, onTap: () => Navigator.pop(ctx, false)),
          ],
        ),
      ),
    ),
  );
}

/// Card for an advance booking: total, paid online, and what the artist has to collect.
/// [onReceivedLater] shows an "I Received It" button (used after the artist answered No).
class PaymentSummaryCard extends StatelessWidget {
  final PaymentSummary summary;
  final bool busy;
  final VoidCallback? onReceivedLater;

  const PaymentSummaryCard({super.key, required this.summary, this.busy = false, this.onReceivedLater});

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final settled = !s.hasBalanceDue;
    final Color accent = settled ? AiraColors.success : const Color(0xFF8A6A1F);
    final String headline = settled
        ? 'Fully Paid'
        : (s.notReceived ? '${_rs(s.balanceDue)} Still To Collect' : '${_rs(s.balanceDue)} To Collect From The Customer');

    Widget row(String l, String v, {bool bold = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(l, style: AiraText.sans(fontSize: 13, color: AiraColors.charcoalSoft))),
          Text(v, style: AiraText.sans(fontSize: 13, fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
        ],
      ),
    );

    return AiraCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(settled ? Icons.check_circle_rounded : Icons.payments_outlined, color: accent, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(headline, style: AiraText.sans(fontSize: 14.5, fontWeight: FontWeight.w800, color: accent))),
          ]),
          const SizedBox(height: 8),
          row('Booking Total', _rs(s.totalAmount)),
          row('Paid Online', _rs(s.paidAmount)),
          if (s.hasBalanceDue) row('To Collect', _rs(s.balanceDue), bold: true),
          if (s.notReceived && onReceivedLater != null) ...[
            const SizedBox(height: 10),
            GhostButton(label: 'I Received It', icon: Icons.check_rounded, expand: true, onTap: busy ? null : onReceivedLater),
          ],
        ],
      ),
    );
  }
}