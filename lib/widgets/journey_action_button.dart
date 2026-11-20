// FILE: widgets/journey_action_button.dart
// WIDGET: Action button on a booking card — loads the live booking and shows the next journey step.

import 'package:flutter/material.dart';
import '../theme/tokens.dart';
import '../models/models.dart';
import '../models/booking/booking.dart';
import '../models/booking/booking_journey.dart';
import '../models/core/status_item.dart';
import '../helper/booking_stats.dart';
import '../utils/service_locator.dart';
import '../screens/journey_screen.dart';
import 'common.dart';

/// Journey Action Button widget.
class JourneyActionButton extends StatefulWidget {
  final BookingSlot slot;
  final List<StatusItem> statuses;
  final void Function(BookingSlot slot, SlotStatus next, {String? reason}) onUpdateStatus;
  final VoidCallback? onRefresh;
  final bool small;

  /// The booking the parent screen is already showing. When given, the button
  /// uses THIS booking (so the button and the progress card above it can never
  /// disagree) and does not fetch its own copy. When null (booking cards in
  /// lists) the button loads the booking itself, as before.
  final Booking? booking;

  const JourneyActionButton({
    super.key,
    required this.slot,
    required this.statuses,
    required this.onUpdateStatus,
    this.onRefresh,
    this.small = true,
    this.booking,
  });

  @override
  State<JourneyActionButton> createState() => _JourneyActionButtonState();
}

/// State of [JourneyActionButton] — holds the screen data and logic.
class _JourneyActionButtonState extends State<JourneyActionButton> {
  late Future<Booking> _future;

  /// Runs once when the screen opens.
  @override
  void initState() {
    super.initState();
    _future = ServiceLocator.bookingJourneyService.getBooking(widget.slot.bookingId!);
  }

  /// Called when the parent passes new values.
  @override
  void didUpdateWidget(covariant JourneyActionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slot.bookingId != widget.slot.bookingId) {
      _future = ServiceLocator.bookingJourneyService.getBooking(widget.slot.bookingId!);
    }
  }

  /// API: bookingJourneyService.getBooking
  void _refetch() {
    if (mounted) {
      setState(() {
        _future = ServiceLocator.bookingJourneyService.getBooking(widget.slot.bookingId!);
      });
    }
  }

  /// Opens the next screen.
  void _open(BuildContext context) {
    // Navigates to JourneyScreen
    Navigator.of(context)
        .push(MaterialPageRoute(
      builder: (_) => JourneyScreen(
        slot: widget.slot,
        statuses: widget.statuses,
        onUpdateStatus: widget.onUpdateStatus,
        onRefresh: widget.onRefresh,
      ),
    ))
        .then((_) {
      _refetch();
    });
  }

  ({String label, bool enabled}) _labelFor(JourneyStage stage, Booking booking) {
    final slot = widget.slot;
    switch (stage) {
      case JourneyStage.upcoming:
        if (slot.isWithinUpcomingWindow) {
          // In-Salon: no On My Way / Arrived — the artist starts the service when the customer is there.
          return (label: 'Start Service', enabled: true);
        }
        return (label: 'Upcoming', enabled: false);
      case JourneyStage.missed:
        return (label: 'Missed', enabled: false);
      case JourneyStage.onTheWay:
        return (label: 'Start Service', enabled: true);
      case JourneyStage.arrived:
        return (label: 'Start Service', enabled: true);
      case JourneyStage.inProgress:
        return (label: 'Complete Service', enabled: true);
      case JourneyStage.completed:
      // The server's own words: "Completed and Payment Received" only when paid, else just "Completed".
        final serverLabel = booking.statusLabel;
        return (label: (serverLabel != null && serverLabel.isNotEmpty) ? serverLabel : 'Completed and Payment Received', enabled: false);
    }
  }

  /// The button for a given booking.
  Widget _buttonFor(Booking booking) {
    final stage = JourneyStage.fromBooking(
      booking,
      BookingStats.mapStatus(booking.statusId, widget.statuses, cancelledBy: booking.cancelledBy),
    );
    if (booking.cancelledBy != null && booking.cancelledBy!.isNotEmpty) {
      return GhostButton(label: 'Cancelled', small: widget.small, color: AiraColors.charcoalSoft, onTap: null);
    }
    final info = _labelFor(stage, booking);
    if (!info.enabled) {
      return GhostButton(label: info.label, small: widget.small, color: AiraColors.charcoalSoft, onTap: null);
    }
    return PrimaryButton(label: info.label, small: widget.small, onTap: () => _open(context));
  }

  /// Builds the UI.
  @override
  Widget build(BuildContext context) {
    if (widget.slot.bookingId == null) {
      return GhostButton(label: 'Upcoming', small: widget.small, color: AiraColors.charcoalSoft, onTap: null);
    }
    // The parent screen already has the booking → use it (always up to date).
    final given = widget.booking;
    if (given != null) return _buttonFor(given);

    return FutureBuilder<Booking>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return GhostButton(label: 'Upcoming', small: widget.small, color: AiraColors.charcoalSoft, onTap: null);
        }
        return _buttonFor(snapshot.data!);
      },
    );
  }
}