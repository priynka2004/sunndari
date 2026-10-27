// FILE: screens/insights_screen.dart
// SCREEN: Insights — business summary from the server (bookings by status, repeat clients,
// most-booked services, profile views). Earnings are not part of the API yet.
//
// APIs used:
//   GET /artists/insights/summary/        (optional from_date / to_date, dd-mm-yy)
//   GET /artists/bookings/get_all/        (only for the "bookings per week" chart)
//   GET /core/booking-status/get_all/

import 'package:flutter/material.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../models/booking/booking.dart';
import '../models/artist/artist_extras.dart';
import '../models/core/status_item.dart';
import '../utils/service_locator.dart';

/// Insight Item.
class _InsightItem {
  final String tone;
  final String title;
  final String body;
  final IconData icon;
  final String? cta;
  final VoidCallback? onTap;
  const _InsightItem(this.tone, this.title, this.body, this.icon, {this.cta, this.onTap});
}

/// SCREEN: Insights — business score and stats computed on-device from bookings/packages/profile.
class InsightsScreen extends StatefulWidget {
  final void Function(String target, [String? tab]) onNavigate;
  const InsightsScreen({super.key, required this.onNavigate});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

/// State of [InsightsScreen] — holds the screen data and logic.
class _InsightsScreenState extends State<InsightsScreen> {
  bool _loading = true;
  String? _error;
  List<Booking> _bookings = [];
  List<StatusItem> _statuses = [];
  InsightsSummary _insights = const InsightsSummary();

  DateTimeRange? _range;

  /// Runs once when the screen opens; starts: _load().
  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _range = DateTimeRange(start: DateTime(now.year, now.month, 1), end: DateTime(now.year, now.month + 1, 0));
    _load();
  }

  /// Loads this screen's data.
  /// Uses 4 APIs (see inline notes).
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // API call: bookingService.getAllBookings → GET /artists/bookings/get_all/
      final bookings = await ServiceLocator.bookingService.getAllBookings(limit: 200);

      List<StatusItem> statuses = [];
      try {
        // API call: coreService.getBookingStatuses → GET /core/booking-status/get_all/
        statuses = await ServiceLocator.coreService.getBookingStatuses();
      } catch (_) {
      }

      // API call: artistBusiness.getInsights → GET /artists/insights/summary/
      final insights = await ServiceLocator.artistBusiness.getInsights(
        fromDate: _range == null ? null : _ddmmyy(_range!.start),
        toDate: _range == null ? null : _ddmmyy(_range!.end),
      );

      if (!mounted) return;
      setState(() {
        _bookings = bookings;
        _statuses = statuses;
        _insights = insights;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  /// dd-mm-yy, as the insights endpoint expects.
  String _ddmmyy(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${(d.year % 100).toString().padLeft(2, '0')}';

  /// Changes the period and reloads the summary from the server.
  void _applyRange(DateTimeRange? r) {
    setState(() => _range = r);
    _load();
  }

  /// Status label.
  String _statusLabel(int statusId) {
    final m = _statuses.where((s) => s.statusId == statusId);
    return m.isNotEmpty ? m.first.name.toLowerCase() : '';
  }

  /// Lets the user pick range.
  Future<void> _pickRange() async {
    final picked = await pickAiraDateRange(context, initialRange: _range);
    if (picked == null) return;
    _applyRange(picked);
  }

  /// Filtered bookings.
  List<Booking> get _filteredBookings {
    final range = _range;
    if (range == null) return _bookings;
    return _bookings.where((b) {
      final d = DateTime.tryParse(b.bookingDate);
      if (d == null) return false;
      final day = DateTime(d.year, d.month, d.day);
      return !day.isBefore(range.start) && !day.isAfter(range.end);
    }).toList();
  }

  /// Repeat rate.
  double get _repeatRate {
    final completed = _filteredBookings.where((b) => _statusLabel(b.statusId) == 'completed').toList();
    if (completed.isEmpty) return 0;
    final byCustomer = <int, int>{};
    for (final b in completed) {
      byCustomer[b.customerId] = (byCustomer[b.customerId] ?? 0) + 1;
    }
    final repeatCustomers = byCustomer.values.where((c) => c > 1).length;
    return (repeatCustomers / byCustomer.length) * 100;
  }

  /// Completion rate.
  double get _completionRate {
    if (_filteredBookings.isEmpty) return 0;
    final completed = _filteredBookings.where((b) => _statusLabel(b.statusId) == 'completed').length;
    final decided = _filteredBookings
        .where((b) => ['completed', 'cancelled', 'no_show'].contains(_statusLabel(b.statusId)))
        .length;
    if (decided == 0) return 0;
    return (completed / decided) * 100;
  }

  /// Avg booking value.
  double get _avgBookingValue {
    final completed = _filteredBookings.where((b) => _statusLabel(b.statusId) == 'completed').toList();
    if (completed.isEmpty) return 0;
    return completed.fold<double>(0, (s, b) => s + b.totalAmount) / completed.length;
  }

  /// Pending count.
  int get _pendingCount =>
      _filteredBookings.where((b) => _statusLabel(b.statusId) == 'pending').length;

  /// Upcoming count.
  int get _upcomingCount => _filteredBookings.where((b) {
        final label = _statusLabel(b.statusId);
        if (label != 'pending' && label != 'confirmed') return false;
        final d = DateTime.tryParse(b.bookingDate);
        if (d == null) return false;
        final today = DateTime.now();
        final day = DateTime(d.year, d.month, d.day);
        return !day.isBefore(DateTime(today.year, today.month, today.day));
      }).length;

  /// Period label.
  String _periodLabel() {
    final r = _range;
    if (r == null) return 'All Time';
    final now = DateTime.now();
    if (r.start == DateTime(now.year, now.month, 1) && r.end == DateTime(now.year, now.month + 1, 0)) return 'This Month';
    if (r.start == DateTime(now.year, now.month - 1, 1) && r.end == DateTime(now.year, now.month, 0)) return 'Last Month';
    return formatAiraDateRange(r);
  }

  /// Chooses period.
  Future<void> _choosePeriod() async {
    final now = DateTime.now();
    final choice = await showModalBottomSheet<String>(
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
              Text('Show Insights For', style: AiraText.serif(fontSize: 20, fontWeight: FontWeight.w700, color: AiraColors.roseDeep)),
              const SizedBox(height: 8),
              for (final o in const [('this', 'This Month'), ('last', 'Last Month'), ('all', 'All Time'), ('custom', 'Custom Range…')])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(o.$2, style: AiraText.sans(fontSize: 14.5, fontWeight: FontWeight.w600, color: AiraColors.roseDeep)),
                  onTap: () => Navigator.of(ctx).pop(o.$1),
                ),
            ],
          ),
        ),
      ),
    );
    if (choice == null) return;
    switch (choice) {
      case 'this':
        _applyRange(DateTimeRange(start: DateTime(now.year, now.month, 1), end: DateTime(now.year, now.month + 1, 0)));
      case 'last':
        _applyRange(DateTimeRange(start: DateTime(now.year, now.month - 1, 1), end: DateTime(now.year, now.month, 0)));
      case 'all':
        _applyRange(null);
      default:
        await _pickRange();
    }
  }

  bool _cancelled(Booking b) {
    final l = _statusLabel(b.statusId);
    return l.contains('cancel') || l.contains('reject') || l.contains('no_show') || (b.cancelledBy ?? '').isNotEmpty;
  }

  /// UI piece: stat.
  Widget _stat(IconData icon, String label, String value) => AiraCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            SunndariIconBubble(icon: icon, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AiraText.sans(fontSize: 12, fontWeight: FontWeight.w700, color: AiraColors.roseDeep)),
                  Text(value, style: AiraText.sans(fontSize: 22, fontWeight: FontWeight.w800, color: AiraColors.charcoal)),
                ],
              ),
            ),
          ],
        ),
      );

  /// UI piece: empty block.
  Widget _emptyBlock(IconData icon, String title, String body) => AiraCard(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: const BoxDecoration(color: AiraColors.blush, shape: BoxShape.circle),
              child: Icon(icon, size: 34, color: AiraColors.rose),
            ),
            const SizedBox(height: 12),
            Text(title, textAlign: TextAlign.center, style: AiraText.sans(fontSize: 14.5, fontWeight: FontWeight.w800, color: AiraColors.roseDeep)),
            const SizedBox(height: 4),
            Text(body, textAlign: TextAlign.center, style: AiraText.sans(fontSize: 12, color: AiraColors.charcoalSoft, height: 1.4)),
          ],
        ),
      );

  /// Top services straight from the API (already sorted by bookings).
  List<MapEntry<String, int>> _topServices() =>
      _insights.topServices.map((t) => MapEntry(t.name, t.bookings)).toList();

  /// See all services.
  void _seeAllServices(List<MapEntry<String, int>> all) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AiraColors.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Most Booked Services', style: AiraText.serif(fontSize: 20, fontWeight: FontWeight.w700, color: AiraColors.roseDeep)),
            const SizedBox(height: 10),
            if (all.isEmpty)
              Text('Nothing To Show Yet.', style: AiraText.sans(color: AiraColors.charcoalSoft))
            else
              for (final e in all)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(child: Text(e.key, style: AiraText.sans(fontSize: 14, fontWeight: FontWeight.w600))),
                      Text('${e.value} booking${e.value == 1 ? '' : 's'}', style: AiraText.sans(fontSize: 12.5, color: AiraColors.charcoalSoft)),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }

  /// Builds the UI.
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.4, color: AiraColors.rose));
    }
    if (_error != null) return AiraErrorState(message: _error!, onRetry: _load);

    final top = _topServices();

    final now = DateTime.now();
    final weekStart = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    final weeks = List.generate(6, (i) => weekStart.subtract(Duration(days: 7 * (5 - i))));
    final perWeek = weeks.map((w) {
      final end = w.add(const Duration(days: 7));
      return _bookings.where((b) {
        if (_cancelled(b)) return false;
        final d = DateTime.tryParse(b.bookingDate);
        return d != null && !d.isBefore(w) && d.isBefore(end);
      }).length;
    }).toList();
    final maxWeek = perWeek.fold<int>(0, (m, v) => v > m ? v : m);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        AiraCard(
          onTap: _choosePeriod,
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const SunndariIconBubble(icon: Icons.calendar_month_outlined, size: 42),
              const SizedBox(width: 12),
              Expanded(child: Text(_periodLabel(), style: AiraText.sans(fontSize: 15, fontWeight: FontWeight.w800, color: AiraColors.roseDeep))),
              const Icon(Icons.keyboard_arrow_down_rounded, color: AiraColors.rose, size: 26),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _stat(Icons.calendar_month_outlined, 'Bookings', '${_insights.totalBookings}')),
            const SizedBox(width: 10),
            Expanded(child: _stat(Icons.task_alt_rounded, 'Completed', '${_insights.completedBookings}')),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _stat(Icons.people_outline_rounded, 'Repeat Clients', '${_insights.repeatClients}')),
            const SizedBox(width: 10),
            Expanded(child: _stat(Icons.visibility_outlined, 'Profile Views', '${_insights.profileViews}')),
          ],
        ),
        if (_insights.bookingsByStatus.isNotEmpty) ...[
          const SizedBox(height: 10),
          AiraCard(
            padding: const EdgeInsets.all(14),
            child: Wrap(
              spacing: 18,
              runSpacing: 8,
              children: [
                for (final e in _insights.bookingsByStatus.entries)
                  Text('${e.key.replaceAll('_', ' ')}: ${e.value}',
                      style: AiraText.sans(fontSize: 12.5, fontWeight: FontWeight.w600, color: AiraColors.roseDeep)),
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(child: Text('Most Booked Services', style: AiraText.serif(fontSize: 19, fontWeight: FontWeight.w700))),
            GestureDetector(
              onTap: () => _seeAllServices(top),
              child: Text('See All  ›', style: AiraText.sans(fontSize: 12.5, fontWeight: FontWeight.w700, color: AiraColors.rose)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (top.isEmpty)
          _emptyBlock(Icons.receipt_long_outlined, 'Insights Appear After Your First Bookings.',
              'Your Most Booked Services Will Be Shown Here Once You Start Receiving Bookings.')
        else
          AiraCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                for (final e in top.take(3))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(e.key, style: AiraText.sans(fontSize: 13.5, fontWeight: FontWeight.w700, color: AiraColors.roseDeep))),
                            Text('${e.value}', style: AiraText.sans(fontSize: 13.5, fontWeight: FontWeight.w800)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(
                            value: e.value / top.first.value,
                            minHeight: 7,
                            backgroundColor: AiraColors.blush,
                            valueColor: const AlwaysStoppedAnimation(AiraColors.rose),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 18),
        Text('Your Growth', style: AiraText.serif(fontSize: 19, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        if (maxWeek == 0)
          _emptyBlock(Icons.bar_chart_rounded, 'See Trends As Your Business Grows.',
              'Your Bookings Per Week Will Appear Here Once You Start Receiving Bookings.')
        else
          AiraCard(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Bookings Per Week', style: AiraText.sans(fontSize: 12.5, color: AiraColors.charcoalSoft)),
                const SizedBox(height: 12),
                SizedBox(
                  height: 110,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var i = 0; i < perWeek.length; i++)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text('${perWeek[i]}', style: AiraText.sans(fontSize: 11, fontWeight: FontWeight.w700)),
                                const SizedBox(height: 4),
                                Container(
                                  height: 8 + 70 * perWeek[i] / maxWeek,
                                  decoration: BoxDecoration(
                                    color: i == perWeek.length - 1 ? AiraColors.roseDeep : AiraColors.pinkBorder,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text('Last 6 Weeks', style: AiraText.sans(fontSize: 11, color: AiraColors.charcoalSoft)),
              ],
            ),
          ),
      ],
    );
  }
}
