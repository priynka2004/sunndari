// FILE: widgets/available_slots_picker.dart
// WIDGET: Shows the artist's hourly slots for ONE date instead of a free time field.
//   Available = green outline, Booked = yellow, Blocked / outside working hours = red / grey, Selected = filled.
//   The slot of the booking being rescheduled ([excludeBookingId]) is treated as free (old slot available).
//
// APIs used (read only):
//   GET /artists/availability/schedule/get_all/
//   GET /artists/availability/block/get_all/
//   GET /artists/bookings/get_all/

import 'package:flutter/material.dart';
import '../theme/tokens.dart';
import '../utils/service_locator.dart';

const _cAvail = AiraColors.success;
const _cBooked = Color(0xFFE0A100);
const _cBlock = AiraColors.errorText;

/// Slot picker for a fixed [date].
class AvailableSlotsPicker extends StatefulWidget {
  final DateTime date;
  final int? excludeBookingId;
  final TimeOfDay? selected;
  final ValueChanged<TimeOfDay> onSelected;

  /// Length of the booking being rescheduled (minutes). When null it is read from the bookings list.
  final int? durationMinutes;

  /// Original start of the booking being rescheduled — marked "Current" on the grid.
  final TimeOfDay? originalStart;

  const AvailableSlotsPicker({
    super.key,
    required this.date,
    required this.onSelected,
    this.excludeBookingId,
    this.selected,
    this.durationMinutes,
    this.originalStart,
  });

  @override
  State<AvailableSlotsPicker> createState() => _AvailableSlotsPickerState();
}

enum _S { available, booked, blocked, closed }

class _AvailableSlotsPickerState extends State<AvailableSlotsPicker> {
  bool _loading = true;
  int? _workStart, _workEnd; // minutes; null = not working that day
  final List<List<int>> _blocks = []; // [start, end] minutes; full day = [0, 1440]
  final List<List<int>> _booked = [];
  int _duration = 60; // length of the booking being rescheduled (minutes)

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AvailableSlotsPicker old) {
    super.didUpdateWidget(old);
    if (old.date != widget.date) {
      setState(() => _loading = true);
      _load();
    }
  }

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  int? _min(dynamic v) {
    final p = v?.toString().split(':');
    if (p == null || p.length < 2) return null;
    final h = int.tryParse(p[0]), m = int.tryParse(p[1]);
    return (h == null || m == null) ? null : h * 60 + m;
  }

  List<dynamic> _list(dynamic j) => j is List ? j : (j is Map && j['data'] is List ? j['data'] as List : const []);

  Future<void> _load() async {
    final iso = _iso(widget.date);
    final dow = widget.date.weekday - 1;
    int? ws, we;
    final blocks = <List<int>>[], booked = <List<int>>[];
    var duration = widget.durationMinutes ?? 60;
    try {
      final art = ServiceLocator.artistService;
      for (final r in _list(await art.getAllSchedules())) {
        if (r is Map && r['dayOfWeek'] == dow) {
          ws = _min(r['startTime']);
          we = _min(r['endTime']);
        }
      }
      for (final b in _list(await art.getAllBlocks())) {
        if (b is! Map) continue;
        final d = (b['blockDate'] ?? b['block_date'])?.toString() ?? '';
        if (d.length < 10 || d.substring(0, 10) != iso) continue;
        final st = _min(b['startTime'] ?? b['start_time']), en = _min(b['endTime'] ?? b['end_time']);
        blocks.add(st == null || en == null ? [0, 1440] : [st, en]);
      }
      final all = await ServiceLocator.bookingService.getAllBookings(limit: 100);
      for (final b in all) {
        if (b.bookingDate != iso || b.cancelledBy != null) continue;
        final st = _min(b.startTime);
        if (st == null) continue;
        if (b.bookingId == widget.excludeBookingId) {
          // This is the booking being rescheduled: its old slot stays available and sets the duration.
          final en = _min(b.endTime);
          if (widget.durationMinutes == null && en != null && en > st) duration = en - st;
          continue;
        }
        final en = (_min(b.endTime) ?? st + 60) + b.returnBufferMinutes;
        booked.add([st, en]);
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _workStart = ws;
      _workEnd = we;
      _duration = duration;
      _blocks
        ..clear()
        ..addAll(blocks);
      _booked
        ..clear()
        ..addAll(booked);
      _loading = false;
    });
  }

  bool _overlap(List<List<int>> rs, int s, int e) => rs.any((r) => s < r[1] && e > r[0]);

  _S _state(int s) {
    final e = s + _duration;
    final now = DateTime.now();
    final isToday = widget.date.year == now.year && widget.date.month == now.month && widget.date.day == now.day;
    if (_workStart == null || _workEnd == null || s < _workStart! || e > _workEnd!) return _S.closed;
    // Server rule: a reschedule must start at least 2 hours from now.
    if (isToday && s < now.hour * 60 + now.minute + 120) return _S.closed;
    if (_overlap(_blocks, s, e)) return _S.blocked;
    if (_overlap(_booked, s, e)) return _S.booked;
    return _S.available;
  }

  String _label(int m) {
    final h = (m ~/ 60) % 24;
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:${(m % 60).toString().padLeft(2, '0')} ${h >= 12 ? 'PM' : 'AM'}';
  }

  Widget _legend(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
            color: c.withOpacity(0.18), borderRadius: BorderRadius.circular(4), border: Border.all(color: c, width: 1.4))),
    const SizedBox(width: 6),
    Text(t, style: AiraText.sans(fontSize: 12.5, fontWeight: FontWeight.w600, color: AiraColors.roseDeep)),
  ]);

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2.4, color: AiraColors.rose)),
      );
    }
    if (_workStart == null || _workEnd == null) {
      return Text('The Artist Is Not Working On This Day.',
          style: AiraText.sans(fontSize: 13.5, color: AiraColors.charcoalSoft));
    }
    final starts = <int>[for (var m = _workStart!; m + 60 <= _workEnd!; m += 60) m];
    if (starts.isEmpty) {
      return Text('No Slots On This Day.', style: AiraText.sans(fontSize: 13.5, color: AiraColors.charcoalSoft));
    }
    final sel = widget.selected == null ? null : widget.selected!.hour * 60 + widget.selected!.minute;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(spacing: 14, runSpacing: 6, children: [
          _legend(_cAvail, 'Available'),
          _legend(_cBooked, 'Booked'),
          _legend(_cBlock, 'Blocked'),
        ]),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: _duration > 60 ? 2 : 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 2.3,
          children: [
            for (final s in starts)
              Builder(builder: (_) {
                final st = _state(s);
                final picked = sel == s;
                final c = switch (st) {
                  _S.available => _cAvail,
                  _S.booked => _cBooked,
                  _S.blocked => _cBlock,
                  _S.closed => AiraColors.charcoalSoft,
                };
                final ok = st == _S.available;
                return GestureDetector(
                  onTap: ok ? () => widget.onSelected(TimeOfDay(hour: s ~/ 60, minute: s % 60)) : null,
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: picked ? AiraColors.roseDeep : c.withOpacity(st == _S.closed ? 0.08 : 0.16),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: picked ? AiraColors.roseDeep : c, width: 1.5),
                    ),
                    child: Text(
                        (_duration > 60 ? '${_label(s)} – ${_label(s + _duration)}' : _label(s)) +
                            (widget.originalStart != null &&
                                widget.originalStart!.hour * 60 + widget.originalStart!.minute == s
                                ? '\n(Current)'
                                : ''),
                        textAlign: TextAlign.center,
                        style: AiraText.sans(
                            fontSize: _duration > 60 ? 11.5 : 13.5,
                            fontWeight: FontWeight.w700,
                            color: picked
                                ? Colors.white
                                : (ok ? AiraColors.charcoal : AiraColors.charcoalSoft.withOpacity(0.8)))),
                  ),
                );
              }),
          ],
        ),
      ],
    );
  }
}