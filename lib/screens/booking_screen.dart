import 'dart:async';
// FILE: screens/booking_screen.dart
// SCREEN: Bookings tab — list of bookings (Upcoming / Completed / Cancelled) with search and filters.

import 'package:flutter/material.dart';
import '../models/models.dart';
import '../models/core/status_item.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/journey_action_button.dart';
import '../utils/service_locator.dart';
import '../models/booking/booking_reschedule.dart';
import 'booking_detail_screen.dart';
import 'business_details_screen.dart';

/// SCREEN: Bookings tab — list of bookings (Upcoming / Completed / Cancelled) with search and filters.
class BookingScreen extends StatefulWidget {
  final List<BookingSlot> slots;
  final bool loading;
  final void Function(BookingSlot slot, SlotStatus next, {String? reason})? onUpdateStatus;
  final List<StatusItem> statuses;
  final VoidCallback? onRefresh;

  /// Switches the main tab (e.g. 'calendar') — used instead of opening a second copy of a tab screen.
  final void Function(String target, [String? tab])? onNavigate;

  const BookingScreen({
    super.key,
    required this.slots,
    this.loading = false,
    this.onUpdateStatus,
    this.statuses = const [],
    this.onRefresh,
    this.onNavigate,
  });

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

/// State of [BookingScreen] — holds the screen data and logic.
class _BookingScreenState extends State<BookingScreen> {
  late DateTime _selectedDate;
  String _tab = 'requests';
  final _search = TextEditingController();

  DateTimeRange? _customRange;

  /// Iso date.
  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Frees controllers / listeners when the screen closes.
  @override
  void dispose() {
    _missedTicker?.cancel();
    _search.dispose();
    super.dispose();
  }

  /// Runs once when the screen opens; starts: _loadReschedules().
  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
    _loadReschedules();
    // Re-evaluate Missed every 30s so Accept disappears the moment the appointment time passes.
    _missedTicker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  Timer? _missedTicker;

  Map<int, BookingReschedule> _reschedules = {};

  /// Loads reschedules.
  /// API: rescheduleService.all
  Future<void> _loadReschedules() async {
    final m = await ServiceLocator.rescheduleService.all();
    if (mounted) setState(() => _reschedules = m);
  }

  /// Returns true if it has pending reschedule.
  bool _hasPendingReschedule(BookingSlot s) =>
      s.bookingId != null &&
          (_reschedules[s.bookingId]?.isPending ?? false) &&
          s.status == SlotStatus.confirmed;

  /// Next30 days.
  List<DateTime> get _next30Days {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return List.generate(30, (i) => today.add(Duration(days: i)));
  }

  /// Slots for selected day.
  List<BookingSlot> get _slotsForSelectedDay {
    final iso = _isoDate(_selectedDate);
    final list = widget.slots.where((s) => s.date == iso).toList();
    list.sort((a, b) => a.time.compareTo(b.time));
    return list;
  }

  /// Slots grouped for range.
  List<MapEntry<String, List<BookingSlot>>> get _slotsGroupedForRange {
    final range = _customRange;
    if (range == null) return const [];
    final startIso = _isoDate(range.start);
    final endIso = _isoDate(range.end);
    final inRange = widget.slots.where((s) => s.date.compareTo(startIso) >= 0 && s.date.compareTo(endIso) <= 0).toList();
    final byDate = <String, List<BookingSlot>>{};
    for (final s in inRange) {
      byDate.putIfAbsent(s.date, () => []).add(s);
    }
    for (final list in byDate.values) {
      list.sort((a, b) => a.time.compareTo(b.time));
    }
    final entries = byDate.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return entries;
  }

  /// Clash descriptions.
  List<String> get _clashDescriptions {
    final active = _slotsForSelectedDay
        .where((s) => s.status != SlotStatus.cancelled && s.status != SlotStatus.noShow && s.status != SlotStatus.completed)
        .toList();
    final byTime = <String, List<BookingSlot>>{};
    for (final s in active) {
      byTime.putIfAbsent(s.time, () => []).add(s);
    }
    final out = <String>[];
    for (final entry in byTime.entries) {
      if (entry.value.length > 1) {
        final who = entry.value.map((s) => s.client).join(' & ');
        out.add('$who Overlap At ${entry.key}');
      }
    }
    return out;
  }

  /// Lets the user pick range.
  Future<void> _pickRange() async {
    final picked = await pickAiraDateRange(context, initialRange: _customRange);
    if (picked == null) return;
    setState(() => _customRange = picked);
  }

  /// Date header label.
  String _dateHeaderLabel(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${weekdays[d.weekday - 1]}, ${d.day} ${months[d.month - 1]}';
  }

  /// Status bg.
  Color _statusBg(SlotStatus s) => switch (s) {
    SlotStatus.pending => AiraColors.goldSoft,
    SlotStatus.confirmed => const Color(0xFFEAF3EC),
    SlotStatus.completed => const Color(0xFFEAF3EC),
    SlotStatus.inProgress => AiraColors.goldSoft,
    SlotStatus.open => AiraColors.bg,
    SlotStatus.clash => AiraColors.errorBg,
    SlotStatus.cancelled => AiraColors.errorBg,
    SlotStatus.noShow => AiraColors.errorBg,
  };
  /// Status text.
  Color _statusText(SlotStatus s) => switch (s) {
    SlotStatus.pending => AiraColors.warn,
    SlotStatus.confirmed => AiraColors.success,
    SlotStatus.completed => AiraColors.success,
    SlotStatus.inProgress => AiraColors.warn,
    SlotStatus.open => AiraColors.charcoalSoft,
    SlotStatus.clash => AiraColors.errorText,
    SlotStatus.cancelled => AiraColors.errorText,
    SlotStatus.noShow => AiraColors.errorText,
  };
  /// Status label.
  String _statusLabel(SlotStatus s) => switch (s) {
    SlotStatus.pending => 'New Request',
    SlotStatus.confirmed => 'Confirmed',
    SlotStatus.completed => 'Completed',
    SlotStatus.inProgress => 'In Progress',
    SlotStatus.open => 'Open',
    SlotStatus.clash => 'Clash',
    SlotStatus.cancelled => 'Cancelled',
    SlotStatus.noShow => 'No-show',
  };

  /// Returns true if missed.
  /// Missed rules (never for completed / cancelled / in-progress bookings):
  /// - Pending request: Missed as soon as the scheduled time has passed (Accept is no longer possible).
  /// - Confirmed booking whose service was never started: Missed once the scheduled time + 2h grace
  ///   (time to still mark "On my way") has passed, or the date is already in the past.
  /// A booking accepted before its time is NOT auto-missed while it is still on time.
  bool _isMissed(BookingSlot s) {
    if (s.status == SlotStatus.pending) {
      final start = s.startDateTime;
      return s.isPastDate || (start != null && !DateTime.now().isBefore(start));
    }
    if (s.status == SlotStatus.confirmed) return s.isMissed;
    return false;
  }

  /// Display status label.
  String _displayStatusLabel(BookingSlot s) {
    if (_isMissed(s)) return 'Missed';
    if (_hasPendingReschedule(s)) {
      return _reschedules[s.bookingId]!.fromCustomer ? 'Reschedule Request' : 'Reschedule Requested';
    }
    if (s.status == SlotStatus.confirmed && s.isFutureDate) return 'Upcoming';
    return _statusLabel(s.status);
  }

  /// Display status bg.
  Color _displayStatusBg(BookingSlot s) =>
      _isMissed(s) ? AiraColors.errorBg : (_hasPendingReschedule(s) ? AiraColors.goldSoft : _statusBg(s.status));
  /// Display status text.
  Color _displayStatusText(BookingSlot s) =>
      _isMissed(s) ? AiraColors.errorText : (_hasPendingReschedule(s) ? const Color(0xFF8A6A1F) : _statusText(s.status));

  /// UI piece: slot tile.
  Widget _slotTile(BookingSlot s) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: AiraCard(
              padding: const EdgeInsets.all(13),
              borderColor: s.status == SlotStatus.clash ? const Color(0xFFF0C3B7) : AiraColors.hair,
              onTap: s.bookingId == null
                  ? null
                  : () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => BookingDetailScreen(
                  bookingId: s.bookingId!,
                  slot: s,
                  onUpdateStatus: widget.onUpdateStatus,
                  statuses: widget.statuses,
                  onRefresh: widget.onRefresh,
                ),
              )).then((_) => _loadReschedules()),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${s.bookingId != null ? 'Booking #${s.bookingId} • ' : ''}${_dateHeaderLabel(s.date)} • ${s.time}',
                                style: AiraText.sans(fontSize: 11.5, color: AiraColors.charcoalSoft)),
                            const SizedBox(height: 2),
                            Text(s.client == '—' ? s.service : s.client,
                                style: AiraText.sans(fontSize: 14, fontWeight: FontWeight.w700, color: AiraColors.roseDeep)),
                            if (s.client != '—')
                              Text(s.service, style: AiraText.sans(fontSize: 12, color: AiraColors.charcoalSoft)),
                            if (s.amount != null)
                              Text('₹${s.amount!.toStringAsFixed(0)}',
                                  style: AiraText.sans(fontSize: 11.5, color: AiraColors.charcoalSoft)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: _displayStatusBg(s), borderRadius: BorderRadius.circular(999)),
                        child: Text(_displayStatusLabel(s),
                            style: AiraText.sans(fontSize: 10.5, fontWeight: FontWeight.w600, color: _displayStatusText(s))),
                      ),
                    ],
                  ),
                  if (widget.onUpdateStatus != null &&
                      s.bookingId != null &&
                      (s.status == SlotStatus.pending ||
                          s.status == SlotStatus.confirmed ||
                          s.status == SlotStatus.inProgress)) ...[
                    const SizedBox(height: 10),
                    if (_isMissed(s))
                      Row(
                        children: [
                          GhostButton(
                            label: 'Cancel',
                            small: true,
                            color: AiraColors.errorText,
                            onTap: () async {
                              final reason = await showAiraCancelReasonDialog(context, clientName: s.client);
                              if (reason == null) return;
                              widget.onUpdateStatus!(s, SlotStatus.cancelled, reason: reason);
                            },
                          ),
                        ],
                      )
                    else if (s.status == SlotStatus.pending)
                      Row(
                        children: [
                          PrimaryButton(
                            label: 'Accept',
                            small: true,
                            onTap: () {
                              // Re-check at tap time: the appointment time may have passed while the list was open.
                              if (_isMissed(s)) {
                                setState(() {});
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                    content: Text('This Booking Time Has Passed, So It Can No Longer Be Accepted.')));
                                return;
                              }
                              widget.onUpdateStatus!(s, SlotStatus.confirmed);
                            },
                          ),
                          const SizedBox(width: 8),
                          GhostButton(
                            label: 'Reject',
                            small: true,
                            color: AiraColors.errorText,
                            onTap: () async {
                              final reason = await showAiraCancelReasonDialog(context, clientName: s.client, isReject: true);
                              if (reason == null) return;
                              widget.onUpdateStatus!(s, SlotStatus.cancelled, reason: reason);
                            },
                          ),
                        ],
                      )
                    else
                      Row(
                        children: [
                          JourneyActionButton(
                            slot: s,
                            statuses: widget.statuses,
                            onUpdateStatus: widget.onUpdateStatus!,
                            onRefresh: widget.onRefresh,
                          ),
                          const SizedBox(width: 8),
                          GhostButton(
                            label: 'Cancel',
                            small: true,
                            color: AiraColors.errorText,
                            onTap: () async {
                              final reason = await showAiraCancelReasonDialog(context, clientName: s.client);
                              if (reason == null) return;
                              widget.onUpdateStatus!(s, SlotStatus.cancelled, reason: reason);
                            },
                          ),
                        ],
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// In range.
  bool _inRange(BookingSlot s) {
    final r = _customRange;
    if (r == null) return true;
    return s.date.compareTo(_isoDate(r.start)) >= 0 && s.date.compareTo(_isoDate(r.end)) <= 0;
  }

  /// Matches search.
  bool _matchesSearch(BookingSlot s) {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return true;
    return s.client.toLowerCase().contains(q) ||
        s.service.toLowerCase().contains(q) ||
        '${s.bookingId ?? ''}'.contains(q);
  }

  /// Returns true if request.
  bool _isRequest(BookingSlot s) => s.status == SlotStatus.pending && !_isMissed(s);
  /// Returns true if upcoming.
  bool _isUpcoming(BookingSlot s) =>
      (s.status == SlotStatus.confirmed || s.status == SlotStatus.inProgress) && !_isMissed(s);
  /// Returns true if completed.
  bool _isCompleted(BookingSlot s) => s.status == SlotStatus.completed;
  /// Missed bookings get their own tab (they no longer sit under Requests / Upcoming).
  bool _isMissedTab(BookingSlot s) => _isMissed(s);

  /// For tab.
  List<BookingSlot> _forTab(String tab) {
    final list = widget.slots
        .where((s) => s.bookingId != null)
        .where(switch (tab) {
      'upcoming' => _isUpcoming,
      'completed' => _isCompleted,
      'missed' => _isMissedTab,
      _ => _isRequest,
    })
        .where(_inRange)
        .where(_matchesSearch)
        .toList();
    list.sort((a, b) {
      final c = a.date.compareTo(b.date);
      return (tab == 'completed' || tab == 'missed') ? -c : (c != 0 ? c : a.time.compareTo(b.time));
    });
    return list;
  }

  /// UI piece: tab pill.
  Widget _tabPill(String key, String label, int count) {
    final on = _tab == key;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tab = key),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 2),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? AiraColors.roseDeep : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: on ? AiraColors.roseDeep : AiraColors.hair),
          ),
          child: FittedBox(fit: BoxFit.scaleDown, child: Text('$label ($count)',
              style: AiraText.sans(fontSize: 12, fontWeight: FontWeight.w700, color: on ? Colors.white : AiraColors.charcoal))),
        ),
      ),
    );
  }

  /// UI piece: ready row.
  Widget _readyRow(IconData icon, String title, String sub, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: AiraCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          SunndariIconBubble(icon: icon, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AiraText.sans(fontSize: 13.5, fontWeight: FontWeight.w800, color: AiraColors.roseDeep)),
                Text(sub, style: AiraText.sans(fontSize: 12, color: AiraColors.charcoalSoft)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AiraColors.rose),
        ],
      ),
    ),
  );

  /// UI piece: empty card.
  Widget _emptyCard(String tab) {
    final (title, body) = switch (tab) {
      'upcoming' => ('No Upcoming Bookings', 'Accepted Bookings Will Show Up Here.'),
      'completed' => ('No Completed Bookings Yet', 'Finished Appointments Will Be Listed Here.'),
      'missed' => ('No Missed Bookings', 'Bookings Whose Time Passed Without Being Completed Will Show Up Here.'),
      _ => ('No Booking Requests Yet', 'New Requests Will Appear Here When A Client Books Your Services.'),
    };
    final searching = _search.text.trim().isNotEmpty || _customRange != null;
    return AiraCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
      child: Column(
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: const BoxDecoration(color: AiraColors.blush, shape: BoxShape.circle),
            child: const Icon(Icons.calendar_month_outlined, size: 38, color: AiraColors.rose),
          ),
          const SizedBox(height: 14),
          Text(searching ? 'No Bookings Match' : title,
              textAlign: TextAlign.center,
              style: AiraText.sans(fontSize: 16, fontWeight: FontWeight.w800, color: AiraColors.roseDeep)),
          const SizedBox(height: 6),
          Text(searching ? 'Try A Different Search Or Date Range.' : body,
              textAlign: TextAlign.center,
              style: AiraText.sans(fontSize: 12.5, color: AiraColors.charcoalSoft, height: 1.4)),
        ],
      ),
    );
  }

  /// Builds the UI.
  @override
  Widget build(BuildContext context) {
    final requests = widget.slots.where((s) => s.bookingId != null && _isRequest(s)).length;
    final upcoming = widget.slots.where((s) => s.bookingId != null && _isUpcoming(s)).length;
    final completed = widget.slots.where((s) => s.bookingId != null && _isCompleted(s)).length;
    final missed = widget.slots.where((s) => s.bookingId != null && _isMissed(s)).length;
    final list = _forTab(_tab);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        if (widget.loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2.4, color: AiraColors.rose)),
          ),
        AiraCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(color: AiraColors.blush, shape: BoxShape.circle),
                child: const Icon(Icons.search_rounded, color: AiraColors.roseDeep, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  cursorColor: AiraColors.roseDeep,
                  style: AiraText.sans(fontSize: 14),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    hintText: 'Search Bookings',
                    hintStyle: AiraText.sans(fontSize: 14, color: AiraColors.charcoalSoft.withOpacity(0.8)),
                  ),
                ),
              ),
              if (_search.text.isNotEmpty)
                GestureDetector(
                  onTap: () => setState(_search.clear),
                  child: const Icon(Icons.close_rounded, size: 18, color: AiraColors.charcoalSoft),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _tabPill('requests', 'Requests', requests),
            const SizedBox(width: 8),
            _tabPill('upcoming', 'Upcoming', upcoming),
            const SizedBox(width: 8),
            _tabPill('completed', 'Completed', completed),
            const SizedBox(width: 8),
            _tabPill('missed', 'Missed', missed),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _customRange == null ? _pickRange : () => setState(() => _customRange = null),
              child: Container(
                width: 44,
                height: 42,
                decoration: BoxDecoration(
                  color: _customRange == null ? Colors.white : AiraColors.blush,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _customRange == null ? AiraColors.hair : AiraColors.rose),
                ),
                child: Icon(_customRange == null ? Icons.tune_rounded : Icons.close_rounded, size: 20, color: AiraColors.roseDeep),
              ),
            ),
          ],
        ),
        if (_customRange != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Showing ${formatAiraDateRange(_customRange!)}',
                style: AiraText.sans(fontSize: 12, color: AiraColors.charcoalSoft)),
          ),
        const SizedBox(height: 14),
        if (!widget.loading && list.isEmpty) _emptyCard(_tab),
        if (list.isNotEmpty) ...list.map(_slotTile),
        const SizedBox(height: 14),
        AiraCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome, size: 34, color: AiraColors.rose),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Stay Ready For Your Next Client',
                            style: AiraText.sans(fontSize: 15, fontWeight: FontWeight.w800, color: AiraColors.roseDeep)),
                        Text('Keep Your Profile And Services Up To Date To Attract More Bookings.',
                            style: AiraText.sans(fontSize: 12, color: AiraColors.charcoalSoft, height: 1.35)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // _readyRow(Icons.calendar_month_outlined, 'Keep Your Calendar Updated', 'Make Sure Your Availability Is Correct.',
              //     // Switches to the Calendar tab (no second copy of the screen)
              //         () => widget.onNavigate?.call('calendar')),
              _readyRow(Icons.receipt_long_outlined, 'Review Your Services & Pricing', 'Keep Your Offerings Fresh And Clear.',
                  // Navigates to BusinessDetailsScreen
                      () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BusinessDetailsScreen(initialTab: 'package')))),
            ],
          ),
        ),
      ],
    );
  }
}