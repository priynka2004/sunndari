// FILE: screens/finance_screen.dart
// SCREEN: Earnings tab — period picker, net earnings, paid vs pending, payout history (computed from bookings).
//
// APIs used:
//   GET /artists/profile/get/

import 'package:flutter/material.dart';
import '../theme/tokens.dart';
import '../utils/service_locator.dart';
import '../widgets/common.dart';
import '../models/booking/booking.dart';
import '../models/core/status_item.dart';
import '../helper/booking_stats.dart';
import 'business_details_screen.dart';

/// Invoice Row.
class InvoiceRow {
  final String label;
  final String amount;
  final String status;
  const InvoiceRow(this.label, this.amount, this.status);
}

/// Enum: Period values.
enum _Period { thisMonth, lastMonth, thisWeek, allTime, custom }

/// SCREEN: Earnings tab — period picker, net earnings, paid vs pending, payout history (computed from bookings).
class FinanceScreen extends StatefulWidget {
  final VoidCallback onWithdraw;
  final bool loading;
  final List<Booking> bookings;
  final List<StatusItem> statuses;
  final Map<int, String> customerNames;

  const FinanceScreen({
    super.key,
    required this.onWithdraw,
    this.loading = false,
    this.bookings = const [],
    this.statuses = const [],
    this.customerNames = const {},
  });

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

/// State of [FinanceScreen] — holds the screen data and logic.
class _FinanceScreenState extends State<FinanceScreen> {
  _Period _period = _Period.thisMonth;
  DateTimeRange? _custom;
  double _commission = 0;
  bool _commissionLoaded = false; // net is shown only once the fee is known (never gross first, then net)

  /// Runs once when the screen opens; starts: _loadCommission().
  @override
  void initState() {
    super.initState();
    _loadCommission();
  }

  /// Loads commission.
  /// API: artistService.getProfile → GET /artists/profile/get/
  Future<void> _loadCommission() async {
    try {
      final p = await ServiceLocator.artistService.getProfile();
      if (mounted) setState(() {
        _commission = p.commissionRate;
        _commissionLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _commissionLoaded = true);
    }
  }

  DateTimeRange? get _range {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_period) {
      case _Period.thisMonth:
        return DateTimeRange(start: DateTime(now.year, now.month, 1), end: DateTime(now.year, now.month + 1, 0));
      case _Period.lastMonth:
        return DateTimeRange(start: DateTime(now.year, now.month - 1, 1), end: DateTime(now.year, now.month, 0));
      case _Period.thisWeek:
        final start = today.subtract(Duration(days: today.weekday - 1));
        return DateTimeRange(start: start, end: start.add(const Duration(days: 6)));
      case _Period.allTime:
        return null;
      case _Period.custom:
        return _custom;
    }
  }

  /// Period label.
  String get _periodLabel => switch (_period) {
        _Period.thisMonth => 'This Month',
        _Period.lastMonth => 'Last Month',
        _Period.thisWeek => 'This Week',
        _Period.allTime => 'All Time',
        _Period.custom => _custom == null ? 'Custom Range' : formatAiraDateRange(_custom!),
      };

  List<Booking> get _filtered {
    final r = _range;
    if (r == null) return widget.bookings;
    return widget.bookings.where((b) {
      final d = DateTime.tryParse(b.bookingDate);
      if (d == null) return false;
      final day = DateTime(d.year, d.month, d.day);
      return !day.isBefore(r.start) && !day.isAfter(r.end);
    }).toList();
  }

  /// Chooses period.
  Future<void> _choosePeriod() async {
    final v = await showModalBottomSheet<_Period>(
      context: context,
      backgroundColor: AiraColors.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Show Earnings For', style: AiraText.serif(fontSize: 20, fontWeight: FontWeight.w700, color: AiraColors.roseDeep)),
              const SizedBox(height: 8),
              for (final p in _Period.values)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    switch (p) {
                      _Period.thisMonth => 'This Month',
                      _Period.lastMonth => 'Last Month',
                      _Period.thisWeek => 'This Week',
                      _Period.allTime => 'All Time',
                      _Period.custom => 'Custom Range…',
                    },
                    style: AiraText.sans(fontSize: 14.5, fontWeight: FontWeight.w600, color: AiraColors.roseDeep),
                  ),
                  trailing: Icon(_period == p ? Icons.radio_button_checked : Icons.radio_button_off, color: AiraColors.rose),
                  onTap: () => Navigator.of(ctx).pop(p),
                ),
            ],
          ),
        ),
      ),
    );
    if (v == null) return;
    if (v == _Period.custom) {
      final picked = await pickAiraDateRange(context, initialRange: _custom);
      if (picked == null) return;
      setState(() {
        _custom = picked;
        _period = _Period.custom;
      });
    } else {
      setState(() => _period = v);
    }
  }

  String _rs(double v) => '₹${v.toStringAsFixed(0)}';

  /// UI piece: stat.
  Widget _stat(IconData icon, String label, String value, {bool wide = false}) => AiraCard(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
        child: wide
            ? Row(
                children: [
                  SunndariIconBubble(icon: icon, size: 44),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: AiraText.sans(fontSize: 11.5, color: AiraColors.charcoalSoft)),
                      Text(value, style: AiraText.sans(fontSize: 20, fontWeight: FontWeight.w800, color: AiraColors.charcoal)),
                    ],
                  ),
                ],
              )
            : Column(
                children: [
                  SunndariIconBubble(icon: icon, size: 40),
                  const SizedBox(height: 8),
                  Text(label, textAlign: TextAlign.center, style: AiraText.sans(fontSize: 11, color: AiraColors.charcoalSoft)),
                  const SizedBox(height: 2),
                  Text(value, style: AiraText.sans(fontSize: 19, fontWeight: FontWeight.w800, color: AiraColors.charcoal)),
                ],
              ),
      );

  /// UI piece: link row.
  Widget _linkRow(IconData icon, String label, VoidCallback onTap) => AiraCard(
        onTap: onTap,
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            SunndariIconBubble(icon: icon, size: 42),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: AiraText.sans(fontSize: 14, fontWeight: FontWeight.w700, color: AiraColors.roseDeep))),
            const Icon(Icons.chevron_right_rounded, color: AiraColors.rose),
          ],
        ),
      );

  /// Shows breakdown.
  void _showBreakdown(BookingStats stats) {
    final rows = stats.recentTransactions;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AiraColors.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.92,
        builder: (ctx, scroll) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Earnings Breakdown', style: AiraText.serif(fontSize: 21, fontWeight: FontWeight.w700, color: AiraColors.roseDeep)),
              Text(_periodLabel, style: AiraText.sans(fontSize: 12.5, color: AiraColors.charcoalSoft)),
              const SizedBox(height: 10),
              Expanded(
                child: rows.isEmpty
                    ? Center(child: Text('No Bookings In This Period.', style: AiraText.sans(color: AiraColors.charcoalSoft)))
                    : ListView.separated(
                        controller: scroll,
                        itemCount: rows.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, color: AiraColors.hair),
                        itemBuilder: (_, i) {
                          final b = rows[i];
                          final label = stats.statusLabel(b.statusId);
                          final fee = b.platformFee ?? (b.totalAmount * _commission / 100);
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(widget.customerNames[b.customerId] ?? 'Customer',
                                          style: AiraText.sans(fontSize: 13.5, fontWeight: FontWeight.w700, color: AiraColors.roseDeep)),
                                      Text('${b.bookingDate} • ${label.isEmpty ? 'booking' : label}',
                                          style: AiraText.sans(fontSize: 11.5, color: AiraColors.charcoalSoft)),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(_rs(b.totalAmount), style: AiraText.sans(fontSize: 13.5, fontWeight: FontWeight.w800)),
                                    Text('Net ${_rs(b.netAmount ?? (b.totalAmount - fee))}',
                                        style: AiraText.sans(fontSize: 11, color: AiraColors.charcoalSoft)),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds the UI.
  @override
  Widget build(BuildContext context) {
    final stats = BookingStats(_filtered, widget.statuses);
    final gross = stats.totalEarnings;
    const adjustments = 0.0;
    // Net comes from each booking's own net amount (older bookings: commission rate).
    final ready = _commissionLoaded || _filtered.every((b) => b.netAmount != null);
    final net = stats.netEarnings(_commission) + adjustments;
    final fees = gross - stats.netEarnings(_commission);
    const paidOut = 0.0;
    final pending = net - paidOut;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        if (widget.loading)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: LinearProgressIndicator(minHeight: 3, color: AiraColors.rose, backgroundColor: AiraColors.blush),
          ),
        AiraCard(
          onTap: _choosePeriod,
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const SunndariIconBubble(icon: Icons.calendar_month_outlined, size: 42),
              const SizedBox(width: 12),
              Expanded(child: Text(_periodLabel, style: AiraText.sans(fontSize: 15, fontWeight: FontWeight.w800, color: AiraColors.roseDeep))),
              const Icon(Icons.keyboard_arrow_down_rounded, color: AiraColors.rose, size: 26),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AiraCard(
          gradient: AiraGradients.financeCard,
          borderWidth: 1,
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          child: Stack(
            children: [
              const Positioned(right: 0, top: 4, child: Icon(Icons.auto_awesome, size: 52, color: AiraColors.pinkBorder)),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Net Earnings', style: AiraText.sans(fontSize: 16, fontWeight: FontWeight.w800, color: AiraColors.roseDeep)),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () => ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(const SnackBar(
                              content: Text('Net Earnings = Gross Earnings − Platform Fees ± Adjustments.'),
                              behavior: SnackBarBehavior.floating)),
                        child: const Icon(Icons.info_outline_rounded, size: 17, color: AiraColors.charcoalSoft),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(ready ? _rs(net) : '…', style: AiraText.serif(fontSize: 46, fontWeight: FontWeight.w800)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _stat(Icons.account_balance_wallet_outlined, 'Gross Earnings', _rs(gross))),
            const SizedBox(width: 8),
            Expanded(child: _stat(Icons.percent_rounded, 'Platform Fees', ready ? _rs(fees) : '…')),
            const SizedBox(width: 8),
            Expanded(child: _stat(Icons.tune_rounded, 'Adjustments', _rs(adjustments))),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _stat(Icons.account_balance_outlined, 'Paid Out', _rs(paidOut), wide: true)),
            const SizedBox(width: 8),
            Expanded(child: _stat(Icons.schedule_rounded, 'Pending Payout', ready ? _rs(pending) : '…', wide: true)),
          ],
        ),
        const SizedBox(height: 10),
        _linkRow(Icons.receipt_long_outlined, 'View Earnings Breakdown', () => _showBreakdown(stats)),
        const SizedBox(height: 18),
        Text('Payout History', style: AiraText.serif(fontSize: 19, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        AiraCard(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            children: [
              const Icon(Icons.calendar_month_outlined, size: 40, color: AiraColors.rose),
              const SizedBox(height: 10),
              Text('No Payouts Yet', style: AiraText.sans(fontSize: 15, fontWeight: FontWeight.w800, color: AiraColors.roseDeep)),
              const SizedBox(height: 4),
              Text('Your Payout History Will Appear Here After Your First Eligible Payment.',
                  textAlign: TextAlign.center,
                  style: AiraText.sans(fontSize: 12, color: AiraColors.charcoalSoft, height: 1.4)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _linkRow(Icons.account_balance_outlined, 'Bank & Payout Settings',
            // Navigates to BusinessDetailsScreen
            () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BusinessDetailsScreen(initialTab: 'kyc')))),
      ],
    );
  }
}
