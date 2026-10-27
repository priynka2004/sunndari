// FILE: screens/edit_working_hours_screen.dart
// SCREEN: Profile → My Business → Edit Working Hours (same look as onboarding).
// Pick the working days, then set the same hours for all days or different hours for each day.
//
// APIs used:
//   GET    /artists/availability/schedule/get_all/
//   POST   /artists/availability/schedule/set/
//   DELETE /artists/availability/schedule/remove/

import 'package:flutter/material.dart';
import '../models/auth/set_schedule.dart';
import '../theme/tokens.dart';
import '../utils/app_feedback.dart';
import '../utils/service_locator.dart';
import '../widgets/common.dart';
import '../widgets/sunndari_time_picker.dart';

/// SCREEN: Edit Working Hours.
class EditWorkingHoursScreen extends StatefulWidget {
  const EditWorkingHoursScreen({super.key});

  @override
  State<EditWorkingHoursScreen> createState() => _EditWorkingHoursScreenState();
}

class _EditWorkingHoursScreenState extends State<EditWorkingHoursScreen> {
  static const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _defStart = TimeOfDay(hour: 9, minute: 0);
  static const _defEnd = TimeOfDay(hour: 18, minute: 0);

  bool _loading = true;
  bool _saving = false;
  bool _perDay = false;
  TimeOfDay _from = _defStart;
  TimeOfDay _to = _defEnd;
  final Set<int> _days = {};
  final Map<int, (TimeOfDay, TimeOfDay)> _dayHours = {};
  final Set<int> _wasScheduled = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<dynamic> _asList(dynamic j) {
    if (j is List) return j;
    if (j is Map && j['data'] is List) return j['data'] as List;
    return const [];
  }

  TimeOfDay _parse(dynamic v, TimeOfDay fallback) {
    final parts = v?.toString().split(':');
    if (parts == null || parts.length < 2) return fallback;
    return TimeOfDay(hour: int.tryParse(parts[0]) ?? fallback.hour, minute: int.tryParse(parts[1]) ?? fallback.minute);
  }

  String _fmt(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  String _label(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    return '$h:${t.minute.toString().padLeft(2, '0')} ${t.period == DayPeriod.am ? 'AM' : 'PM'}';
  }

  int _mins(TimeOfDay t) => t.hour * 60 + t.minute;

  /// Loads the saved weekly schedule.
  /// API: artistService.getAllSchedules
  Future<void> _load() async {
    try {
      final sched = await ServiceLocator.artistService.getAllSchedules();
      for (final r in _asList(sched)) {
        final m = Map<String, dynamic>.from(r as Map);
        final d = m['dayOfWeek'];
        if (d is! int) continue;
        _days.add(d);
        _wasScheduled.add(d);
        _dayHours[d] = (_parse(m['startTime'], _defStart), _parse(m['endTime'], _defEnd));
      }
      if (_dayHours.isNotEmpty) {
        final first = _dayHours.values.first;
        _from = first.$1;
        _to = first.$2;
        // Different timings on different days → open in "different hours by day" mode.
        _perDay = _dayHours.values.any((h) => h.$1 != first.$1 || h.$2 != first.$2);
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pickTime(bool from, {int? day}) async {
    final current = day == null ? (from ? _from : _to) : (from ? _hoursOf(day).$1 : _hoursOf(day).$2);
    final t = await pickSunndariTime(context, initial: current, helpText: from ? 'Start Time' : 'End Time');
    if (t == null) return;
    setState(() {
      if (day == null) {
        from ? _from = t : _to = t;
      } else {
        final h = _hoursOf(day);
        _dayHours[day] = from ? (t, h.$2) : (h.$1, t);
      }
    });
  }

  (TimeOfDay, TimeOfDay) _hoursOf(int d) => _dayHours[d] ?? (_from, _to);

  /// Saves the schedule: set every selected day, remove the days that were switched off.
  /// API: artistService.setSchedule / artistService.removeSchedule
  Future<void> _save() async {
    if (_days.isEmpty) {
      AppFeedback.showWarning(context, 'Please Select At Least One Working Day.');
      return;
    }
    for (final d in _days) {
      final h = _perDay ? _hoursOf(d) : (_from, _to);
      if (_mins(h.$2) <= _mins(h.$1)) {
        AppFeedback.showWarning(context, 'End Time Must Be After Start Time (${_dayNames[d]}).');
        return;
      }
    }
    setState(() => _saving = true);
    try {
      final art = ServiceLocator.artistService;
      for (var d = 0; d < 7; d++) {
        if (_days.contains(d)) {
          final h = _perDay ? _hoursOf(d) : (_from, _to);
          await art.setSchedule(SetSchedule(dayOfWeek: d, startTime: _fmt(h.$1), endTime: _fmt(h.$2)));
        } else if (_wasScheduled.contains(d)) {
          await art.removeSchedule(d);
        }
      }
      if (!mounted) return;
      AppFeedback.showSuccess(context, 'Working Hours Saved ✓');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) AppFeedback.showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _timeBox(String label, TimeOfDay t, VoidCallback onTap) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AiraText.sans(fontSize: 13, color: AiraColors.charcoalSoft)),
            const SizedBox(height: 4),
            GestureDetector(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: AiraColors.pinkFill,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AiraColors.pinkBorder),
                ),
                child: Row(children: [
                  Expanded(child: Text(_label(t), style: AiraText.sans(fontSize: 15, fontWeight: FontWeight.w700))),
                  const Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: AiraColors.roseDeep),
                ]),
              ),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final sorted = _days.toList()..sort();
    return Scaffold(
      backgroundColor: AiraColors.bg,
      body: SunndariBackground(
        child: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4, color: AiraColors.rose))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  children: [
                    SunndariAppBar(onBack: () => Navigator.of(context).pop()),
                    const SunndariPageHeading(
                        title: 'Edit Working Hours', subtitle: 'Set The Days And Hours Clients Can Book You.'),
                    const SizedBox(height: 14),
                    Text('Working Days',
                        style: AiraText.sans(fontSize: 16, fontWeight: FontWeight.w800, color: AiraColors.roseDeep)),
                    const SizedBox(height: 10),
                    Row(children: [
                      for (var d = 0; d < 7; d++) ...[
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _days.contains(d) ? _days.remove(d) : _days.add(d)),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: _days.contains(d) ? AiraColors.roseDeep : AiraColors.pinkFill,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: _days.contains(d) ? AiraColors.roseDeep : AiraColors.pinkBorder),
                              ),
                              child: Text(_dayNames[d],
                                  style: AiraText.sans(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: _days.contains(d) ? Colors.white : AiraColors.roseDeep)),
                            ),
                          ),
                        ),
                        if (d != 6) const SizedBox(width: 5),
                      ],
                    ]),
                    const SizedBox(height: 18),
                    Text('Working Hours',
                        style: AiraText.sans(fontSize: 16, fontWeight: FontWeight.w800, color: AiraColors.roseDeep)),
                    const SizedBox(height: 10),
                    if (!_perDay)
                      Row(children: [
                        _timeBox('From', _from, () => _pickTime(true)),
                        const SizedBox(width: 12),
                        _timeBox('To', _to, () => _pickTime(false)),
                      ])
                    else
                      for (final d in sorted)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            SizedBox(
                                width: 42,
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Text(_dayNames[d],
                                      style: AiraText.sans(
                                          fontSize: 14, fontWeight: FontWeight.w800, color: AiraColors.roseDeep)),
                                )),
                            _timeBox('From', _hoursOf(d).$1, () => _pickTime(true, day: d)),
                            const SizedBox(width: 10),
                            _timeBox('To', _hoursOf(d).$2, () => _pickTime(false, day: d)),
                          ]),
                        ),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () => setState(() {
                        _perDay = !_perDay;
                        if (_perDay) {
                          for (final d in _days) {
                            _dayHours.putIfAbsent(d, () => (_from, _to));
                          }
                        }
                      }),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(children: [
                          Icon(_perDay ? Icons.toggle_on_rounded : Icons.toggle_off_rounded,
                              size: 34, color: _perDay ? AiraColors.success : AiraColors.charcoalSoft),
                          const SizedBox(width: 8),
                          Text('Set Different Hours By Day',
                              style: AiraText.sans(fontSize: 14, fontWeight: FontWeight.w700, color: AiraColors.rose)),
                        ]),
                      ),
                    ),
                    Text(_perDay ? 'Each Selected Day Has Its Own Hours.' : 'These Hours Apply To All Selected Days.',
                        style: AiraText.sans(fontSize: 13, color: AiraColors.charcoalSoft)),
                    const SizedBox(height: 22),
                    PrimaryButton(
                      label: _saving ? 'Saving…' : 'Save Working Hours',
                      expand: true,
                      onTap: _saving ? null : _save,
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
