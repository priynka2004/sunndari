import '../utils/payment_status.dart';
// FILE: models/models.dart  |  MODEL
// UI booking slot model (BookingSlot) + SlotStatus used by Bookings / Calendar screens.

/// Enum: Slot Status values.
enum SlotStatus { pending, confirmed, inProgress, completed, cancelled, noShow, open, clash }

/// Model: Booking Slot.
class BookingSlot {
  final int? bookingId;
  final String date;
  final String time;
  final String client;
  final String service;
  final SlotStatus status;
  final double? amount;
  final String? rawStartTime;
  /// "HH:mm:ss" end of the booking (start + package duration + add-ons) — the calendar uses it to block the whole time.
  final String? rawEndTime;
  /// The status in words made by the server ("Confirmed", "Completed and Payment Received", …) — shown as is.
  final String? statusLabel;
  /// Raw payment status from the server (`partially_paid`, `paid`, …).
  final String? paymentStatus;

  const BookingSlot({
    this.bookingId,
    required this.date,
    required this.time,
    required this.client,
    required this.service,
    required this.status,
    this.amount,
    this.rawStartTime,
    this.rawEndTime,
    this.statusLabel,
    this.paymentStatus,
  });

  /// Completed service whose payment is still partial / in progress.
  bool get paymentInProgress => status == SlotStatus.completed && PaymentStatusX.isInProgress(paymentStatus);

  /// Starts date time.
  DateTime? get startDateTime {
    final d = DateTime.tryParse(date);
    if (d == null || rawStartTime == null) return null;
    final parts = rawStartTime!.split(':');
    if (parts.isEmpty) return null;
    final h = int.tryParse(parts[0]);
    final m = parts.length > 1 ? int.tryParse(parts[1]) : 0;
    if (h == null) return null;
    return DateTime(d.year, d.month, d.day, h, m ?? 0);
  }

  /// Returns true if within upcoming window.
  bool get isWithinUpcomingWindow {
    final start = startDateTime;
    if (start == null) return false;
    final now = DateTime.now();
    final diff = now.difference(start).abs();
    return diff <= const Duration(hours: 2);
  }

  /// Returns true if it has start time passed.
  bool get hasStartTimePassed {
    final start = startDateTime;
    if (start == null) return isBookingDay;
    return !DateTime.now().isBefore(start);
  }

  /// Returns true if future date.
  bool get isFutureDate {
    final d = DateTime.tryParse(date);
    if (d == null) return false;
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    return DateTime(d.year, d.month, d.day).isAfter(todayOnly);
  }

  /// Returns true if booking day.
  bool get isBookingDay {
    final d = DateTime.tryParse(date);
    if (d == null) return false;
    final today = DateTime.now();
    return d.year == today.year && d.month == today.month && d.day == today.day;
  }

  /// Returns true if past date.
  bool get isPastDate {
    final d = DateTime.tryParse(date);
    if (d == null) return false;
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    return DateTime(d.year, d.month, d.day).isBefore(todayOnly);
  }

  /// Returns true if missed.
  bool get isMissed {
    if (isPastDate) return true;
    final start = startDateTime;
    if (start == null) return false;
    return DateTime.now().isAfter(start.add(const Duration(hours: 2)));
  }

  /// Returns a copy with some fields changed.
  BookingSlot copyWith({String? date, String? time, String? client, String? service, SlotStatus? status}) {
    return BookingSlot(
      bookingId: bookingId,
      date: date ?? this.date,
      time: time ?? this.time,
      client: client ?? this.client,
      service: service ?? this.service,
      status: status ?? this.status,
      amount: amount,
      rawStartTime: rawStartTime,
      // A changed status makes the server's words for the old one stale.
      statusLabel: status == null ? statusLabel : null,
      paymentStatus: paymentStatus,
    );
  }
}