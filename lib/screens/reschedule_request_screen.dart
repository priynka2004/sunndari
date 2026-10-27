// FILE: screens/reschedule_request_screen.dart
// SCREEN: Reschedule Request — customer asked to move a booking; artist accepts / suggests another time / declines.

import 'package:flutter/material.dart';
import '../models/booking/booking_reschedule.dart';
import '../theme/tokens.dart';
import '../utils/app_feedback.dart';
import '../utils/service_locator.dart';
import '../widgets/common.dart';
import '../widgets/reschedule_widgets.dart';
import '../widgets/available_slots_picker.dart';

/// SCREEN: Reschedule Request — customer asked to move a booking; artist accepts / suggests another time / declines.
class RescheduleRequestScreen extends StatefulWidget {
  final BookingReschedule request;
  final String clientName;
  final String serviceName;

  const RescheduleRequestScreen({
    super.key,
    required this.request,
    required this.clientName,
    required this.serviceName,
  });

  @override
  State<RescheduleRequestScreen> createState() => _RescheduleRequestScreenState();
}

/// State of [RescheduleRequestScreen] — holds the screen data and logic.
class _RescheduleRequestScreenState extends State<RescheduleRequestScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String doneMessage) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      AppFeedback.showSuccess(context, doneMessage);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) AppFeedback.showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Accepts the request.
  /// API: rescheduleService.accept
  Future<void> _accept() => _run(
        // API call: rescheduleService.accept
        () => ServiceLocator.rescheduleService.accept(widget.request),
        'Reschedule Accepted ✓ Booking Updated',
      );

  /// Declines the request.
  /// API: rescheduleService.decline
  Future<void> _decline() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Decline Reschedule?', style: AiraText.serif(fontSize: 19)),
        content: Text(
          '${widget.clientName} Will Be Told The Booking Stays At ${RescheduleFmt.dateTime(widget.request.oldStart)}.',
          style: AiraText.sans(fontSize: 13.5, color: AiraColors.charcoalSoft, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Keep Reviewing', style: AiraText.sans(fontWeight: FontWeight.w700, color: AiraColors.roseDeep)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Decline', style: AiraText.sans(fontWeight: FontWeight.w700, color: AiraColors.errorText)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    // API call: rescheduleService.decline
    await _run(() => ServiceLocator.rescheduleService.decline(widget.request), 'Request Declined');
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

  /// Bottom sheet with the day's available / booked slots (no free time entry).
  Future<TimeOfDay?> _pickSlot(DateTime date) {
    TimeOfDay? picked;
    return showModalBottomSheet<TimeOfDay>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AiraColors.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Choose An Available Slot', style: AiraText.serif(fontSize: 20)),
                const SizedBox(height: 4),
                Text('${date.day}/${date.month}/${date.year}',
                    style: AiraText.sans(fontSize: 14, fontWeight: FontWeight.w700, color: AiraColors.rose)),
                const SizedBox(height: 12),
                AvailableSlotsPicker(
                  date: date,
                  excludeBookingId: widget.request.bookingId,
                  selected: picked,
                  onSelected: (t) => setSheet(() => picked = t),
                ),
                const SizedBox(height: 16),
                PrimaryButton(
                  label: 'Send Suggestion',
                  expand: true,
                  onTap: picked == null ? null : () => Navigator.of(ctx).pop(picked),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// API: rescheduleService.suggestAnother
  Future<void> _suggest() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      helpText: 'Suggest Another Date',
      initialDate: widget.request.newStart.isAfter(now) ? widget.request.newStart : now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      builder: _themed,
    );
    if (d == null || !mounted) return;
    final t = await _pickSlot(d);
    if (t == null || !mounted) return;
    final suggested = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    if (!suggested.isAfter(now)) {
      AppFeedback.showInfo(context, 'Choose A Time In The Future');
      return;
    }
    await _run(
      // API call: rescheduleService.suggestAnother
      () => ServiceLocator.rescheduleService.suggestAnother(widget.request, suggested),
      'Suggestion Sent: ${RescheduleFmt.dateTime(suggested)}',
    );
  }

  /// Builds the UI.
  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    return Scaffold(
      backgroundColor: AiraColors.bg,
      body: SunndariBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SunndariAppBar(onBack: _busy ? null : () => Navigator.of(context).pop(false)),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(bottom: 14),
                      child: SunndariPageHeading(
                        title: 'Reschedule Request',
                        subtitle: 'Your Client Would Like To Change The Time.',
                      ),
                    ),
                    AiraCard(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: const BoxDecoration(color: AiraColors.blush, shape: BoxShape.circle),
                            child: const Icon(Icons.person_outline_rounded, color: AiraColors.roseDeep, size: 24),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Client', style: AiraText.sans(fontSize: 11.5, color: AiraColors.charcoalSoft)),
                                Text(widget.clientName,
                                    style: AiraText.sans(fontSize: 17, fontWeight: FontWeight.w800, color: AiraColors.roseDeep)),
                                Text(widget.serviceName, style: AiraText.sans(fontSize: 12.5, color: AiraColors.charcoalSoft)),
                              ],
                            ),
                          ),
                          const ReschedulePill('Reschedule Request'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    AiraCard(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Old Vs New Time', style: AiraText.serif(fontSize: 17)),
                          const SizedBox(height: 10),
                          RescheduleCompareCard(
                            oldStart: r.oldStart,
                            newStart: r.newStart,
                            oldLabel: 'Old Date & Time',
                            newLabel: 'New Requested',
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
                          Text('Client’s Reason', style: AiraText.serif(fontSize: 17)),
                          const SizedBox(height: 4),
                          RescheduleInfoRow(
                            icon: Icons.edit_note_rounded,
                            label: 'Reason',
                            value: r.reason.isEmpty ? '—' : r.reason,
                            last: r.note.isEmpty,
                          ),
                          if (r.note.isNotEmpty)
                            RescheduleInfoRow(icon: Icons.notes_rounded, label: 'Note', value: r.note, last: true),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    AiraCard(
                      padding: const EdgeInsets.all(12),
                      backgroundColor: const Color(0xFFFFF6DD),
                      borderColor: AiraColors.warn,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline_rounded, size: 18, color: AiraColors.warn),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Check Your Calendar And Travel Time Before Accepting. '
                              'If You Accept, The Booking Moves To The New Time.',
                              style: AiraText.sans(fontSize: 12.5, color: AiraColors.charcoal, height: 1.35),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    PrimaryButton(
                      label: _busy ? 'Please Wait…' : 'Accept',
                      icon: Icons.check_rounded,
                      expand: true,
                      onTap: _busy ? null : _accept,
                    ),
                    const SizedBox(height: 10),
                    GhostButton(
                      label: 'Suggest Another Time',
                      icon: Icons.edit_calendar_outlined,
                      expand: true,
                      onTap: _busy ? null : _suggest,
                    ),
                    const SizedBox(height: 10),
                    GhostButton(
                      label: 'Decline',
                      icon: Icons.close_rounded,
                      expand: true,
                      color: AiraColors.errorText,
                      onTap: _busy ? null : _decline,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
