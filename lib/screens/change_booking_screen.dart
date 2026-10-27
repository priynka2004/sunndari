// FILE: screens/change_booking_screen.dart
// SCREEN: Change a Booking — step 1 of reschedule (new date/time/reason) or cancel.

import 'package:flutter/material.dart';
import '../theme/tokens.dart';
import '../utils/app_feedback.dart';
import '../widgets/common.dart';
import 'reschedule_review_screen.dart';
import 'reschedule_confirmed_screen.dart';
import '../widgets/available_slots_picker.dart';

/// Reschedule Request.
class RescheduleRequest {
  final DateTime date;
  final TimeOfDay time;
  final String reason;
  final String note;
  const RescheduleRequest({required this.date, required this.time, required this.reason, this.note = ''});
}

/// SCREEN: Change a Booking — step 1 of reschedule (new date/time/reason) or cancel.
class ChangeBookingScreen extends StatefulWidget {
  final int bookingId;
  final String clientName;
  final DateTime currentStart;
  final String serviceName;
  final String dateLabel;
  final String timeLabel;
  final String venueLabel;
  final VoidCallback? onCancelBooking;
  final int? durationMinutes; // booking length, so the slots match it

  const ChangeBookingScreen({
    super.key,
    required this.bookingId,
    required this.clientName,
    required this.currentStart,
    required this.serviceName,
    required this.dateLabel,
    required this.timeLabel,
    required this.venueLabel,
    this.onCancelBooking,
    this.durationMinutes,
  });

  @override
  State<ChangeBookingScreen> createState() => _ChangeBookingScreenState();
}

/// State of [ChangeBookingScreen] — holds the screen data and logic.
class _ChangeBookingScreenState extends State<ChangeBookingScreen> {
  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  static const _reasons = [
    'Personal Emergency',
    'Travel Or Logistics Issue',
    'Calendar Clash',
    'Client Asked For A Change',
    'Other',
  ];

  bool _reschedule = true;
  // The booking's original date stays fixed; only the time slot can change.
  late final DateTime _date = DateTime(widget.currentStart.year, widget.currentStart.month, widget.currentStart.day);
  TimeOfDay? _time;
  String? _reason;
  final _note = TextEditingController();

  /// Frees controllers / listeners when the screen closes.
  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  /// UI piece: themed.
  Widget _themed(BuildContext context, Widget? child) => Theme(
    data: Theme.of(context).copyWith(
      colorScheme: Theme.of(context).colorScheme.copyWith(
        primary: AiraColors.rose,
        onPrimary: Colors.white,
        surface: AiraColors.card,
        onSurface: AiraColors.charcoal,
      ),
    ),
    child: child!,
  );

  /// Lets the user pick reason.
  Future<void> _pickReason() async {
    final r = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Reason For Reschedule', style: AiraText.serif(fontSize: 20)),
              const SizedBox(height: 10),
              for (final r in _reasons)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(r, style: AiraText.sans(fontSize: 14.5, fontWeight: FontWeight.w600, color: AiraColors.roseDeep)),
                  trailing: Icon(
                    _reason == r ? Icons.radio_button_checked : Icons.radio_button_off,
                    color: AiraColors.rose,
                  ),
                  onTap: () => Navigator.of(ctx).pop(r),
                ),
            ],
          ),
        ),
      ),
    );
    if (r != null) setState(() => _reason = r);
  }

  /// Submits the form.
  Future<void> _submit() async {
    if (_time == null || _reason == null) {
      AppFeedback.showInfo(context, 'Pick An Available Time Slot And A Reason First');
      return;
    }
    final newStart = DateTime(_date.year, _date.month, _date.day, _time!.hour, _time!.minute);
    if (!newStart.isAfter(DateTime.now())) {
      AppFeedback.showInfo(context, 'Choose A Time In The Future');
      return;
    }
    if (newStart.isAtSameMomentAs(widget.currentStart)) {
      AppFeedback.showInfo(context, 'That Is The Same As The Current Booking Time');
      return;
    }
    final note = _note.text.trim();

    // Navigates to RescheduleReviewScreen
    final sent = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => RescheduleReviewScreen(
        bookingId: widget.bookingId,
        serviceName: widget.serviceName,
        venueLabel: widget.venueLabel,
        clientName: widget.clientName,
        oldStart: widget.currentStart,
        newStart: newStart,
        reason: _reason!,
        note: note,
      ),
    ));
    if (sent != true || !mounted) return;

    // Navigates to RescheduleConfirmedScreen
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RescheduleConfirmedScreen(
        serviceName: widget.serviceName,
        clientName: widget.clientName,
        oldStart: widget.currentStart,
        newStart: newStart,
      ),
    ));
    if (!mounted) return;
    Navigator.of(context).pop(RescheduleRequest(date: _date, time: _time!, reason: _reason!, note: note));
  }

  /// Builds the UI.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AiraColors.bg,
      body: SunndariBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SunndariAppBar(onBack: () => Navigator.of(context).pop()),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(bottom: 14),
                      child: SunndariPageHeading(
                        title: 'Change A Booking',
                        subtitle: 'Reschedule Or Cancel Your Booking.',
                      ),
                    ),
                    _summary(),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AiraColors.hair),
                      ),
                      child: Row(
                        children: [
                          _seg('Reschedule', Icons.calendar_month_outlined, _reschedule, () => setState(() => _reschedule = true)),
                          _seg('Cancel Booking', Icons.cancel_outlined, !_reschedule, () => setState(() => _reschedule = false)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (_reschedule) ..._rescheduleForm() else _cancelCard(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// UI piece: summary.
  Widget _summary() => AiraCard(
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Booking Summary', style: AiraText.serif(fontSize: 17)),
        const SizedBox(height: 10),
        Row(
          children: [
            Container(
              width: 78,
              height: 88,
              decoration: BoxDecoration(
                gradient: AiraGradients.avatarOrb,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.face_retouching_natural, size: 32, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.serviceName, style: AiraText.sans(fontSize: 15, fontWeight: FontWeight.w700, color: AiraColors.roseDeep)),
                  const SizedBox(height: 4),
                  _meta(Icons.calendar_today_outlined, widget.dateLabel),
                  _meta(Icons.schedule_rounded, widget.timeLabel),
                  _meta(Icons.location_on_outlined, widget.venueLabel),
                ],
              ),
            ),
          ],
        ),
      ],
    ),
  );

  /// UI piece: meta.
  Widget _meta(IconData i, String t) => Padding(
    padding: const EdgeInsets.only(top: 3),
    child: Row(
      children: [
        Icon(i, size: 14, color: AiraColors.rose),
        const SizedBox(width: 6),
        Expanded(child: Text(t, style: AiraText.sans(fontSize: 12.5, color: AiraColors.charcoalSoft))),
      ],
    ),
  );

  /// UI piece: seg.
  Widget _seg(String label, IconData icon, bool on, VoidCallback onTap) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: on ? AiraColors.roseDeep : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: on ? Colors.white : AiraColors.roseDeep),
            const SizedBox(width: 8),
            Text(label,
                style: AiraText.sans(fontSize: 13.5, fontWeight: FontWeight.w700, color: on ? Colors.white : AiraColors.roseDeep)),
          ],
        ),
      ),
    ),
  );

  /// Reschedule form.
  List<Widget> _rescheduleForm() {
    final dateText = '${_date.day} ${_months[_date.month - 1]} ${_date.year}';
    return [
      AiraCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Booking Date', style: AiraText.sans(fontSize: 14.5, fontWeight: FontWeight.w800, color: AiraColors.roseDeep)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                color: AiraColors.blush,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AiraColors.pinkBorder, width: 1.1),
              ),
              child: Row(children: [
                const Icon(Icons.calendar_today_outlined, size: 18, color: AiraColors.rose),
                const SizedBox(width: 10),
                Expanded(child: Text(dateText, style: AiraText.sans(fontSize: 15, fontWeight: FontWeight.w700, color: AiraColors.charcoal))),
                const Icon(Icons.lock_outline_rounded, size: 17, color: AiraColors.charcoalSoft),
              ]),
            ),
            const SizedBox(height: 4),
            Text('The Booking Date Stays The Same. Choose A New Time Slot.',
                style: AiraText.sans(fontSize: 12.5, color: AiraColors.charcoalSoft)),
            const SizedBox(height: 14),
            Text('Available Time Slots', style: AiraText.sans(fontSize: 14.5, fontWeight: FontWeight.w800, color: AiraColors.roseDeep)),
            const SizedBox(height: 8),
            AvailableSlotsPicker(
              date: _date,
              excludeBookingId: widget.bookingId,
              durationMinutes: widget.durationMinutes,
              originalStart: TimeOfDay(hour: widget.currentStart.hour, minute: widget.currentStart.minute),
              selected: _time,
              onSelected: (t) => setState(() => _time = t),
            ),
            const SizedBox(height: 16),
            _selectField('Reason For Reschedule', Icons.edit_note_rounded, _reason ?? 'Select A Reason', _reason != null, _pickReason),
            Text('Additional Note (Optional)',
                style: AiraText.sans(fontSize: 13.5, fontWeight: FontWeight.w800, color: AiraColors.roseDeep)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
              decoration: BoxDecoration(
                color: AiraColors.pinkFill,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AiraColors.pinkBorder, width: 1.1),
              ),
              child: Column(
                children: [
                  TextField(
                    controller: _note,
                    maxLines: 3,
                    maxLength: 300,
                    onChanged: (_) => setState(() {}),
                    style: AiraText.sans(fontSize: 14),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      counterText: '',
                      icon: const Icon(Icons.edit_note_rounded, size: 20, color: AiraColors.rose),
                      hintText: 'Add A Note (Optional)',
                      hintStyle: AiraText.sans(fontSize: 13.5, color: AiraColors.charcoalSoft.withOpacity(0.7)),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text('${_note.text.length}/300', style: AiraText.sans(fontSize: 11, color: AiraColors.charcoalSoft)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      AiraCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Check Before Requesting', style: AiraText.serif(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            _check(Icons.people_outline_rounded, 'Client Confirmation Required'),
            _check(Icons.event_available_outlined, 'Availability Checked For Service And Travel Time'),
            _check(Icons.info_outline_rounded, 'Any Price Change Shown Before Confirmation', last: true),
          ],
        ),
      ),
      const SizedBox(height: 12),
      AiraCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const SunndariIconBubble(icon: Icons.toll_outlined, size: 38),
            const SizedBox(width: 12),
            Expanded(child: Text('Applicable Charges', style: AiraText.sans(fontSize: 13.5, fontWeight: FontWeight.w800, color: AiraColors.roseDeep))),
            Text('Calculated Before Submission', style: AiraText.sans(fontSize: 11.5, color: AiraColors.charcoalSoft)),
          ],
        ),
      ),
      const SizedBox(height: 16),
      PrimaryButton(label: 'Review Reschedule Request', arrow: true, expand: true, onTap: _submit),
      const SizedBox(height: 6),
      Center(
        child: TextButton(
          onPressed: () => setState(() => _reschedule = false),
          child: Text('View Cancellation Options',
              style: AiraText.sans(fontSize: 12.5, fontWeight: FontWeight.w700, color: AiraColors.rose)
                  .copyWith(decoration: TextDecoration.underline)),
        ),
      ),
    ];
  }

  /// UI: checks.
  Widget _check(IconData i, String t, {bool last = false}) => Container(
    padding: const EdgeInsets.symmetric(vertical: 9),
    decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: AiraColors.hair))),
    child: Row(
      children: [
        SunndariIconBubble(icon: i, size: 34),
        const SizedBox(width: 10),
        Expanded(child: Text(t, style: AiraText.sans(fontSize: 13, color: AiraColors.charcoal))),
      ],
    ),
  );

  /// UI: selects field.
  Widget _selectField(String label, IconData icon, String value, bool filled, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AiraText.sans(fontSize: 13.5, fontWeight: FontWeight.w800, color: AiraColors.roseDeep)),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: AiraColors.pinkFill,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AiraColors.pinkBorder, width: 1.1),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: AiraColors.rose),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(value,
                      style: AiraText.sans(fontSize: 14, color: filled ? AiraColors.charcoal : AiraColors.charcoalSoft.withOpacity(0.8))),
                ),
                const Icon(Icons.keyboard_arrow_down_rounded, color: AiraColors.rose),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  /// UI piece: cancel card.
  Widget _cancelCard() => AiraCard(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Cancel This Booking?', style: AiraText.serif(fontSize: 18)),
        const SizedBox(height: 6),
        Text(
          'The Client Is Told Right Away, With The Reason You Give. Applicable Cancellation Charges Are Calculated Before Submission.',
          style: AiraText.sans(fontSize: 13, color: AiraColors.charcoalSoft, height: 1.4),
        ),
        const SizedBox(height: 14),
        GhostButton(
          label: 'Cancel Booking',
          icon: Icons.close_rounded,
          expand: true,
          color: AiraColors.errorText,
          onTap: widget.onCancelBooking == null
              ? () => AppFeedback.showInfo(context, 'Cancellation Is Available From The Booking List')
              : widget.onCancelBooking,
        ),
      ],
    ),
  );
}