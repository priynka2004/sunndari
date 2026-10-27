// FILE: screens/calendar_screen.dart
// SCREEN: Calendar tab — month view, bookings per day, block days / hours.
// (Working hours are edited from Profile → My Business → Edit Working Hours.)
//
// APIs used:
//   GET /artists/availability/schedule/get_all/
//   GET /artists/availability/block/get_all/
//   POST /artists/availability/block/add/

import 'package:flutter/material.dart';
import '../models/auth/add_block.dart';
import '../models/models.dart';
import '../models/core/status_item.dart';
import '../models/booking/booking_reschedule.dart';
import 'booking_detail_screen.dart';
import '../theme/tokens.dart';
import '../utils/app_feedback.dart';
import '../utils/service_locator.dart';
import '../widgets/common.dart';

/// SCREEN: Calendar tab — month view, bookings per day, block days / hours.
class CalendarScreen extends StatefulWidget {
  final bool showBack;

  final List<BookingSlot> slots;
  final List<StatusItem> statuses;
  final void Function(BookingSlot slot, SlotStatus next, {String? reason})? onUpdateStatus;
  final VoidCallback? onRefresh;

  const CalendarScreen({
    super.key,
    this.showBack = false,
    this.slots = const [],
    this.statuses = const [],
    this.onUpdateStatus,
    this.onRefresh,
  });

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

/// State of [CalendarScreen] — holds the screen data and logic.
class _CalendarScreenState extends State<CalendarScreen> {
  static const _dayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _dayLong = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  late DateTime _selected;
  String _view = 'month'; // 'month' | 'day'
  bool _loading = true;
  bool _saving = false;

  final Map<int, bool> _available = {};
  final Map<int, TimeOfDay> _start = {};
  final Map<int, TimeOfDay> _end = {};
  Set<String> _blocked = {}; // dates blocked for the WHOLE day
  final Map<String, List<List<int>>> _partial = {}; // date -> blocked ranges [startMin, endMin]
  final Set<String> _onServer = {}; // dates that already have time-range blocks on the server
  final Set<String> _dirty = {}; // dates with unsaved slot changes

  /// Runs once when the screen opens; starts: _load(), _loadReschedules().
  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selected = DateTime(now.year, now.month, now.day);
    _load();
    _loadReschedules();
  }

  Map<int, BookingReschedule> _reschedules = {};

  /// Loads reschedules.
  /// API: rescheduleService.all
  Future<void> _loadReschedules() async {
    // API call: rescheduleService.all
    final m = await ServiceLocator.rescheduleService.all();
    if (mounted) setState(() => _reschedules = m);
  }

  /// Returns true if live.
  bool _isLive(BookingSlot s) => s.status == SlotStatus.confirmed || s.status == SlotStatus.inProgress;

  /// Bookings on.
  List<BookingSlot> _bookingsOn(DateTime d) =>
      widget.slots.where((s) => s.bookingId != null && _isLive(s) && s.date == _iso(d)).toList();

  /// Slot badge.
  String _slotBadge(BookingSlot s) {
    final r = _reschedules[s.bookingId];
    if (r != null && r.isPending) return r.fromCustomer ? 'Reschedule Request' : 'Reschedule Requested';
    return s.status == SlotStatus.inProgress ? 'In Progress' : 'Confirmed';
  }

  /// Opens booking.
  void _openBooking(BookingSlot s) {
    // Navigates to BookingDetailScreen
    Navigator.of(context)
        .push(MaterialPageRoute(
      builder: (_) => BookingDetailScreen(
        bookingId: s.bookingId!,
        slot: s,
        onUpdateStatus: widget.onUpdateStatus,
        statuses: widget.statuses,
        onRefresh: widget.onRefresh,
      ),
    ))
        .then((_) => _loadReschedules());
  }

  /// Shows booking sheet.
  void _showBookingSheet(BookingSlot s) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const SunndariIconBubble(icon: Icons.event_available_outlined, size: 46),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.client == '—' ? s.service : s.client,
                            style: AiraText.sans(fontSize: 16, fontWeight: FontWeight.w800, color: AiraColors.roseDeep)),
                        Text(s.service, style: AiraText.sans(fontSize: 12.5, color: AiraColors.charcoalSoft)),
                        Text('${s.time} • ${_slotBadge(s)}',
                            style: AiraText.sans(fontSize: 12.5, fontWeight: FontWeight.w600, color: AiraColors.rose)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                label: 'View Booking',
                icon: Icons.visibility_outlined,
                expand: true,
                onTap: () {
                  Navigator.of(ctx).pop();
                  _openBooking(s);
                },
              ),
              const SizedBox(height: 8),
              Text('Need A Different Time? Open The Booking And Tap Reschedule.',
                  style: AiraText.sans(fontSize: 11.5, color: AiraColors.charcoalSoft)),
            ],
          ),
        ),
      ),
    );
  }

  /// Bookings section.
  List<Widget> _bookingsSection() {
    final list = _bookingsOn(_selected);
    return [
      Text('Bookings', style: AiraText.serif(fontSize: 21)),
      const SizedBox(height: 8),
      if (list.isEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text('No Confirmed Bookings On This Day.',
              style: AiraText.sans(fontSize: 16, color: AiraColors.charcoalSoft)),
        )
      else
        for (final s in list)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AiraCard(
              padding: const EdgeInsets.all(13),
              onTap: () => _showBookingSheet(s),
              child: Row(
                children: [
                  const SunndariIconBubble(icon: Icons.event_note_outlined, size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.time, style: AiraText.sans(fontSize: 13, color: AiraColors.charcoalSoft)),
                        Text(s.client == '—' ? s.service : s.client,
                            style: AiraText.sans(fontSize: 16, fontWeight: FontWeight.w700, color: AiraColors.roseDeep)),
                        Text(s.service, style: AiraText.sans(fontSize: 13.5, color: AiraColors.charcoalSoft)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: (_reschedules[s.bookingId]?.isPending ?? false) ? AiraColors.goldSoft : const Color(0xFFEAF3EC),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(_slotBadge(s),
                            style: AiraText.sans(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: (_reschedules[s.bookingId]?.isPending ?? false)
                                    ? const Color(0xFF8A6A1F)
                                    : AiraColors.success)),
                      ),
                      const SizedBox(height: 6),
                      const Icon(Icons.chevron_right_rounded, size: 20, color: AiraColors.rose),
                    ],
                  ),
                ],
              ),
            ),
          ),
      const SizedBox(height: 8),
    ];
  }

  /// As list.
  List<dynamic> _asList(dynamic j) {
    if (j is List) return j;
    if (j is Map && j['data'] is List) return j['data'] as List;
    return const [];
  }

  TimeOfDay _parse(dynamic v, TimeOfDay fallback) {
    final parts = v?.toString().split(':');
    if (parts == null || parts.length < 2) return fallback;
    return TimeOfDay(
      hour: int.tryParse(parts[0]) ?? fallback.hour,
      minute: int.tryParse(parts[1]) ?? fallback.minute,
    );
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  String _label(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    return '$h:${t.minute.toString().padLeft(2, '0')} ${t.period == DayPeriod.am ? 'AM' : 'PM'}';
  }

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Same day.
  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  void _select(DateTime d) {
    _selected = d;
  }

  /// Minutes since midnight from "HH:MM[:SS]" (null when missing).
  int? _minOrNull(dynamic v) {
    final parts = v?.toString().split(':');
    if (parts == null || parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    return (h == null || m == null) ? null : h * 60 + m;
  }

  String _dateOnly(String e) => e.length >= 10 ? e.substring(0, 10) : e;

  /// Block records as (date, startMin?, endMin?) — start/end are null for a full-day block.
  List<(String, int?, int?)> _blockRecords(dynamic blocks) => [
    for (final b in _asList(blocks))
      if (b is Map && (b['blockDate'] ?? b['block_date']) != null)
        (
        _dateOnly((b['blockDate'] ?? b['block_date']).toString()),
        _minOrNull(b['startTime'] ?? b['start_time']),
        _minOrNull(b['endTime'] ?? b['end_time']),
        ),
  ];

  /// Splits the server's blocks into full-day blocks and time-range blocks.
  void _parseBlocks(dynamic blocks) {
    final full = <String>{};
    _partial.clear();
    _onServer.clear();
    for (final (d, st, en) in _blockRecords(blocks)) {
      if (st == null || en == null) {
        full.add(d);
      } else {
        (_partial[d] ??= []).add([st, en]);
        _onServer.add(d);
      }
    }
    _blocked = full;
  }

  TimeOfDay _tod(int minutes) => TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);

  /// Hourly slots [startMin, endMin] inside the selected day's working hours.
  List<List<int>> _slots() {
    final st = _s.hour * 60 + _s.minute;
    final en = _e.hour * 60 + _e.minute;
    final out = <List<int>>[];
    for (var m = st; m < en; m += 60) {
      out.add([m, m + 60 > en ? en : m + 60]);
    }
    return out;
  }

  bool _slotBlocked(String iso, List<int> slot) =>
      _blocked.contains(iso) ||
          (_partial[iso] ?? const []).any((r) => slot[0] < r[1] && slot[1] > r[0]);

  /// Tap a slot: block it / open it again (merged into ranges for the API).
  void _toggleSlot(List<int> slot) {
    final iso = _iso(_selected);
    if (_blocked.contains(iso)) {
      AppFeedback.showInfo(context, 'This Whole Day Is Blocked. Unblock The Day First.');
      return;
    }
    final slots = _slots();
    final blockedNow = <int>{
      for (final sl in slots)
        if (!_slotBooked(iso, sl) && _slotBlocked(iso, sl)) sl[0],
    };
    blockedNow.contains(slot[0]) ? blockedNow.remove(slot[0]) : blockedNow.add(slot[0]);
    final ranges = <List<int>>[];
    for (final sl in slots) {
      if (!blockedNow.contains(sl[0])) continue;
      if (ranges.isNotEmpty && ranges.last[1] == sl[0]) {
        ranges.last[1] = sl[1];
      } else {
        ranges.add([sl[0], sl[1]]);
      }
    }
    setState(() {
      ranges.isEmpty ? _partial.remove(iso) : _partial[iso] = ranges;
      _dirty.add(iso);
    });
  }

  /// Saves the blocked hours of the selected day.
  /// API: removeBlock (clears the day) → addBlock for every blocked range (with start_time / end_time).
  Future<void> _saveSlots() async {
    final iso = _iso(_selected);
    final ranges = [for (final r in (_partial[iso] ?? const <List<int>>[])) [r[0], r[1]]];
    setState(() => _saving = true);
    try {
      final art = ServiceLocator.artistService;
      if (_onServer.contains(iso)) {
        await art.removeBlock(iso);
        _onServer.remove(iso);
      }
      for (final r in ranges) {
        await art.addBlock(AddBlock(blockDate: iso, startTime: _fmt(_tod(r[0])), endTime: _fmt(_tod(r[1]))));
      }
      if (ranges.isNotEmpty) {
        final check = await art.getAllBlocks();
        final ignored = _blockRecords(check).any((r) => r.$1 == iso && (r.$2 == null || r.$3 == null));
        if (ignored) {
          await art.removeBlock(iso);
          if (mounted) {
            setState(() {
              _partial.remove(iso);
              _dirty.remove(iso);
            });
            AppFeedback.showWarning(context, 'Selected Hours Are Not Supported By The Server Yet. Nothing Was Blocked.');
          }
          return;
        }
        _onServer.add(iso);
      }
      if (mounted) {
        setState(() => _dirty.remove(iso));
        AppFeedback.showSuccess(context, 'Blocked Hours Saved ✓');
      }
    } catch (e) {
      if (mounted) AppFeedback.showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Loads this screen's data.
  /// Uses 2 APIs (see inline notes).
  Future<void> _load() async {
    try {
      final art = ServiceLocator.artistService;
      // API call: artistService.getAllSchedules → GET /artists/availability/schedule/get_all/
      final sched = await art.getAllSchedules();
      // API call: artistService.getAllBlocks → GET /artists/availability/block/get_all/
      final blocks = await art.getAllBlocks();
      for (final r in _asList(sched)) {
        final m = Map<String, dynamic>.from(r as Map);
        final d = m['dayOfWeek'];
        if (d is! int) continue;
        _available[d] = true;
        _start[d] = _parse(m['startTime'], const TimeOfDay(hour: 9, minute: 0));
        _end[d] = _parse(m['endTime'], const TimeOfDay(hour: 18, minute: 0));
      }
      _parseBlocks(blocks);
    } catch (_) {
    }
    if (mounted) setState(() => _loading = false);
  }

  int get _dow => _selected.weekday - 1;
  TimeOfDay get _s => _start[_dow] ?? const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay get _e => _end[_dow] ?? const TimeOfDay(hour: 18, minute: 0);

  /// Asks for confirmation, then blocks / unblocks the selected day (single place for Block Time).
  Future<void> _toggleBlock() async {
    final iso = _iso(_selected);
    final blocked = _blocked.contains(iso);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AiraColors.bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(blocked ? 'Unblock This Day?' : 'Block This Day?', style: AiraText.serif(fontSize: 19)),
        content: Text(
          blocked
              ? 'Clients Will Be Able To Book You On $iso Again.'
              : 'Clients Will Not Be Able To Book You On $iso.',
          style: AiraText.sans(fontSize: 13.5, color: AiraColors.charcoalSoft, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(blocked ? 'Unblock' : 'Block',
                style: AiraText.sans(fontWeight: FontWeight.w700, color: AiraColors.rose)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (blocked) {
      await _unblockDay();
    } else {
      await _blockDay();
    }
  }

  /// Block day.
  /// API: artistService.addBlock → POST /artists/availability/block/add/
  Future<void> _blockDay() async {
    try {
      // API call: artistService.addBlock → POST /artists/availability/block/add/
      await ServiceLocator.artistService.addBlock(AddBlock(blockDate: _iso(_selected)));
      if (!mounted) return;
      setState(() => _blocked.add(_iso(_selected)));
      AppFeedback.showSuccess(context, 'This Day Is Blocked');
    } catch (e) {
      if (mounted) AppFeedback.showError(context, e);
    }
  }

  /// Unblocks the selected day so it persists after reload.
  /// API: artistService.removeBlock → DELETE /artists/availability/block/remove/
  Future<void> _unblockDay() async {
    final iso = _iso(_selected);
    try {
      await ServiceLocator.artistService.removeBlock(iso);
      if (mounted) setState(() => _blocked.remove(iso));
    } catch (e) {
      if (mounted) AppFeedback.showError(context, e);
    }
  }

  /// True for any date before today — these are shown greyed out and cannot be selected.
  bool _isPast(DateTime d) {
    final n = DateTime.now();
    return DateTime(d.year, d.month, d.day).isBefore(DateTime(n.year, n.month, n.day));
  }

  // Booking status colours used across the calendar: Open = Green, Blocked = Red, Booked = Yellow.
  static const _cOpen = AiraColors.success;
  static const _cBlocked = AiraColors.errorText;
  static const _cBooked = Color(0xFFE0A100);

  /// Minute ranges already taken by live bookings on [iso] (1 hour from the start time).
  List<List<int>> _bookedRanges(String iso) {
    final out = <List<int>>[];
    for (final s in widget.slots) {
      if (s.bookingId == null || !_isLive(s) || s.date != iso) continue;
      final st = _minOrNull(s.rawStartTime);
      if (st != null) out.add([st, st + 60]);
    }
    return out;
  }

  bool _slotBooked(String iso, List<int> slot) => _bookedRanges(iso).any((r) => slot[0] < r[1] && slot[1] > r[0]);

  /// Colour of a calendar day: yellow = has booking, red = blocked, green = open, null = not working.
  Color? _dayColor(DateTime d) {
    if (_isPast(d)) return null; // dates that have passed are inactive
    final iso = _iso(d);
    if (_bookingsOn(d).isNotEmpty) return _cBooked;
    if (_blocked.contains(iso)) return _cBlocked;
    if (_available[d.weekday - 1] ?? false) return _cOpen;
    return null;
  }

  Widget _legend(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 14, height: 14, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4))),
    const SizedBox(width: 6),
    Text(t, style: AiraText.sans(fontSize: 13, fontWeight: FontWeight.w600, color: AiraColors.roseDeep)),
  ]);

  /// Day tab: tap hours to block / open them for the selected day. Booked hours show yellow and cannot be changed.
  List<Widget> _daySection() {
    final iso = _iso(_selected);
    final fullDay = _blocked.contains(iso);
    final slots = _slots();
    final working = (_available[_dow] ?? false) && slots.isNotEmpty;

    return [
      if (!working)
        AiraCard(
          child: Text('You Are Not Working On This Day. Add It From Profile → My Business → Edit Working Hours.',
              style: AiraText.sans(fontSize: 14, color: AiraColors.charcoalSoft, height: 1.4)),
        )
      else ...[
        Text('Tap An Hour To Block Or Open It.',
            style: AiraText.sans(fontSize: 14, fontWeight: FontWeight.w700, color: AiraColors.roseDeep)),
        const SizedBox(height: 10),
        Wrap(spacing: 16, runSpacing: 6, children: [
          _legend(_cOpen, 'Open'),
          _legend(_cBlocked, 'Blocked'),
          _legend(_cBooked, 'Booked'),
        ]),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.2,
          children: [
            for (final sl in slots)
              Builder(builder: (_) {
                final now = DateTime.now();
                final isToday = _sameDay(_selected, now);
                // Hours that have already passed today are greyed out and cannot be changed.
                final past = _isPast(_selected) || (isToday && sl[1] <= now.hour * 60 + now.minute);
                final booked = !past && _slotBooked(iso, sl);
                final blocked = !past && !booked && _slotBlocked(iso, sl);
                final c = past ? AiraColors.charcoalSoft : (booked ? _cBooked : (blocked ? _cBlocked : _cOpen));
                return GestureDetector(
                  onTap: past
                      ? null
                      : booked
                      ? () => AppFeedback.showInfo(context, 'This Hour Is Already Booked.')
                      : () => _toggleSlot(sl),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.withOpacity(past ? 0.08 : 0.16),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: past ? c.withOpacity(0.35) : c, width: 1.6),
                    ),
                    child: Text(_label(_tod(sl[0])),
                        style: AiraText.sans(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: past ? AiraColors.charcoalSoft.withOpacity(0.5) : AiraColors.charcoal)),
                  ),
                );
              }),
          ],
        ),
        const SizedBox(height: 14),
        if (_dirty.contains(iso)) ...[
          PrimaryButton(
            label: _saving ? 'Saving…' : 'Save Blocked Hours',
            expand: true,
            onTap: _saving ? null : _saveSlots,
          ),
          const SizedBox(height: 8),
        ],
      ],
      GhostButton(
        label: fullDay ? 'Unblock This Day' : 'Block Full Day',
        icon: fullDay ? Icons.event_available_outlined : Icons.event_busy_outlined,
        expand: true,
        onTap: _toggleBlock,
      ),
      const SizedBox(height: 6),
      Text('Blocked Hours Are Hidden From Clients.',
          style: AiraText.sans(fontSize: 13, color: AiraColors.charcoalSoft)),
      const SizedBox(height: 8),
    ];
  }

  /// UI piece: segment (Month | Day).
  Widget _segment() => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: AiraColors.pinkFill,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: AiraColors.hair),
    ),
    child: Row(
      children: [
        for (final e in {'Bookings': 'month', 'Day': 'day'}.entries)
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _view = e.value),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 11),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: _view == e.value ? AiraGradients.button : null,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(e.key,
                    style: AiraText.sans(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: _view == e.value ? Colors.white : AiraColors.roseDeep,
                    )),
              ),
            ),
          ),
      ],
    ),
  );

  /// How many days ahead the date slider shows (starting today; days that already passed are never shown).
  static const _sliderDays = 90;

  /// UI piece: horizontal date slider (like a flight-booking date strip) — replaces the month grid.
  /// Each day is coloured Open (green) / Blocked (red) / Booked (yellow); tap one to select it.
  Widget _dateSlider() {
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    return AiraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text('${_months[_selected.month - 1]} ${_selected.year}',
                style: AiraText.sans(fontSize: 18, fontWeight: FontWeight.w800, color: AiraColors.roseDeep)),
          ),
          SizedBox(
            height: 88,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _sliderDays,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final d = today.add(Duration(days: i));
                final sel = _sameDay(d, _selected);
                final c = _dayColor(d);
                return GestureDetector(
                  onTap: () => setState(() => _select(d)),
                  child: Container(
                    width: 58,
                    decoration: BoxDecoration(
                      color: sel ? AiraColors.roseDeep.withOpacity(0.10) : c?.withOpacity(0.22),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: sel ? AiraColors.roseDeep : (c ?? AiraColors.hair),
                        width: sel ? 2.4 : 1.4,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_dayShort[d.weekday - 1],
                            style: AiraText.sans(fontSize: 12, fontWeight: FontWeight.w700, color: AiraColors.charcoalSoft)),
                        const SizedBox(height: 2),
                        Text('${d.day}',
                            style: AiraText.sans(
                                fontSize: 20,
                                fontWeight: sel ? FontWeight.w900 : FontWeight.w700,
                                color: AiraColors.charcoal)),
                        const SizedBox(height: 2),
                        Text(_months[d.month - 1].substring(0, 3),
                            style: AiraText.sans(fontSize: 11, color: AiraColors.charcoalSoft)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 16, runSpacing: 6, children: [
            _legend(_cOpen, 'Open'),
            _legend(_cBlocked, 'Blocked'),
            _legend(_cBooked, 'Booked'),
          ]),
        ],
      ),
    );
  }

  /// Builds the UI.
  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: SunndariBackground(
        child: _loading
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4, color: AiraColors.rose))
            : ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            if (widget.showBack) ...[
              SunndariAppBar(onBack: () => Navigator.of(context).pop()),
              const SunndariPageHeading(title: 'My Calendar', subtitle: 'Make Time For Your Next Opportunity.'),
            ] else
              const SunndariTabHeader(title: 'My Calendar', subtitle: 'Make Time For Your Next Opportunity.', flush: true),
            const SizedBox(height: 14),
            _segment(),
            const SizedBox(height: 14),
            _dateSlider(),
            const SizedBox(height: 16),
            Text('${_dayLong[_dow]}, ${_selected.day} ${_months[_selected.month - 1]}',
                style: AiraText.serif(fontSize: 22)),
            const SizedBox(height: 10),
            if (_view == 'month') ..._bookingsSection(),
            if (_view == 'day') ...[
              ..._daySection(),
              ..._bookingsSection(),
            ],
          ],
        ),
      ),
    );
  }
}