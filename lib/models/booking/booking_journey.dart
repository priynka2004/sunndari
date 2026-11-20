// FILE: models/booking/booking_journey.dart  |  MODEL
// Journey stage of a booking (on my way, arrived, in progress...).

import '../models.dart';
import 'booking.dart';

/// Enum: Journey Stage values.
enum JourneyStage {
  upcoming,
  onTheWay,
  arrived,
  inProgress,
  completed,
  missed;
  /// For an In-Salon booking there is no On My Way / Arrived: it stays `upcoming` until the artist taps
  /// Start Service; after that ([startPinRequested]) it is `arrived`, which means "waiting for the customer's
  /// Start Service PIN" — then `inProgress` and `completed` as for every booking.
  static JourneyStage fromBooking(Booking booking, SlotStatus status, {bool startPinRequested = false}) {
    if (status == SlotStatus.completed) return JourneyStage.completed;
    if (status == SlotStatus.inProgress) return JourneyStage.inProgress;
    if (booking.isInSalon) {
      if (booking.hasStartTimePassed) return JourneyStage.missed;
      return startPinRequested ? JourneyStage.arrived : JourneyStage.upcoming;
    }
    if (booking.arrivedAt != null && booking.arrivedAt!.isNotEmpty) {
      return JourneyStage.arrived;
    }
    if (booking.onMyWayAt != null && booking.onMyWayAt!.isNotEmpty) {
      return JourneyStage.onTheWay;
    }
    if (booking.hasStartTimePassed) return JourneyStage.missed;
    return JourneyStage.upcoming;
  }
}

/// Model: Booking Journey.
class BookingJourney {
  final int bookingId;
  final JourneyStage stage;
  final Booking booking;

  const BookingJourney({
    required this.bookingId,
    required this.stage,
    required this.booking,
  });
}