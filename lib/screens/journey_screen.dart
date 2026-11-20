// FILE: screens/journey_screen.dart
// SCREEN: Journey — Start PIN -> In progress -> Completion PIN. Shares live location.
// Home Visit: On My Way + Arrived are marked automatically (no screens for them), straight to the Start PIN.
// In-Salon bookings have no On My Way / Arrived: Start Service -> Start PIN -> In progress -> photo -> Completion PIN.
//
// APIs used:
//   GET /users/address/get/
//   PUT /artists/bookings/on_my_way/
//   PUT /artists/bookings/arrived/
//   PUT /artists/bookings/start_pin/request/      (In-Salon)
//   PUT /artists/bookings/start_pin/verify/
//   PUT /artists/bookings/completion_proof/upload/ (camera photo of the finished service)
//   PUT /artists/bookings/completion_pin/request/
//   PUT /artists/bookings/completion_pin/verify/

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/completion_proof_image.dart';
import '../widgets/advance_payment_widgets.dart';
import '../models/models.dart';
import '../models/booking/booking.dart';
import '../models/booking/booking_journey.dart';
import '../models/core/status_item.dart';
import '../helper/booking_stats.dart';
import '../utils/service_locator.dart';
import '../utils/app_feedback.dart';
import '../utils/geo_utils.dart';
import '../utils/address_geocoder.dart' as geocoder;
import '../api/booking_tracking_socket.dart';
import '../api/booking_journey_service.dart' show JourneyReasonError;
import '../services/firestore_location_service.dart';
import '../utils/app_session.dart';
import 'review_customer_screen.dart';

/// SCREEN: Journey — booking lifecycle: On My Way -> Arrival OTP -> Start PIN -> In progress -> Completion PIN. Shares live location.
class JourneyScreen extends StatefulWidget {
  final BookingSlot slot;
  final List<StatusItem> statuses;
  final void Function(BookingSlot slot, SlotStatus next, {String? reason}) onUpdateStatus;
  final VoidCallback? onRefresh;

  const JourneyScreen({
    super.key,
    required this.slot,
    required this.statuses,
    required this.onUpdateStatus,
    this.onRefresh,
  });

  @override
  State<JourneyScreen> createState() => _JourneyScreenState();
}

/// State of [JourneyScreen] — holds the screen data and logic.
class _JourneyScreenState extends State<JourneyScreen> {
  Booking? _booking;
  bool _loading = true;
  bool _busy = false;

  final _pinController = TextEditingController();

  final _tracking = BookingTrackingSocket();
  final _firestoreLocation = FirestoreLocationService();
  StreamSubscription<Position>? _positionSub;

  double? _myLat;
  double? _myLng;

  geocoder.LatLng? _customerLatLng;
  int? _geocodedForAddressId;

  // Home Visit: the "On My Way" and "I Have Arrived" screens are not shown any more. When the artist opens the
  // journey, the app marks On My Way + Arrived in the background (same two backend calls as before) and
  // goes straight to the screen where the customer's start code is entered.
  bool _advancing = false;
  bool _advanceFailed = false;

  bool _completionRequested = false; // artist already tapped "Complete Service"
  bool _startRequested = false; // In-Salon: artist already tapped "Start Service" (the customer has the start code)

  /// The artist already reviewed the customer for this booking — the
  /// "Review Customer" button must not be offered again.
  bool _customerReviewed = false;

  Timer? _lockTicker;
  Duration? _lockRemaining;
  String? _lockedStageKey;

  /// Booking id.
  int get _bookingId => widget.slot.bookingId!;

  JourneyStage get _stage {
    final b = _booking;
    if (b == null) return JourneyStage.upcoming;
    return JourneyStage.fromBooking(
      b,
      BookingStats.mapStatus(b.statusId, widget.statuses, cancelledBy: b.cancelledBy),
      startPinRequested: _startRequested,
    );
  }

  /// True for an In-Salon booking: no On My Way / Arrived, the artist starts the service with a PIN.
  bool get _isInSalon => _booking?.isInSalon ?? false;

  /// The finished-service photo is on the server.
  bool get _hasCompletionPhoto => _booking?.completionProof != null;

  /// Stage credential key.
  String? get _stageCredentialKey => switch (_stage) {
    JourneyStage.arrived => 'start',
    JourneyStage.inProgress => 'complete',
    _ => null,
  };

  /// Runs once when the screen opens; starts: _load().
  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Frees controllers / listeners when the screen closes.
  @override
  void dispose() {
    _lockTicker?.cancel();
    _positionSub?.cancel();
    _tracking.close();
    _pinController.dispose();
    super.dispose();
  }

  /// Loads this screen's data.
  /// API: bookingJourneyService.getBooking
  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // API call: bookingJourneyService.getBooking
      final booking = await ServiceLocator.bookingJourneyService.getBooking(_bookingId);
      if (!mounted) return;
      setState(() {
        _booking = booking;
        _loading = false;
      });
      _afterBookingChanged();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppFeedback.showError(context, e, onRetry: _load);
    }
  }

  /// After booking changed.
  void _afterBookingChanged() {
    _refreshCompletionRequested();
    _refreshStartRequested();
    _refreshCustomerReviewed();
    // An In-Salon booking has no travel: no live location is shared and there is no customer address to show.
    if (!_isInSalon && (_stage == JourneyStage.onTheWay || _stage == JourneyStage.arrived)) {
      _startLocationSharing();
      _loadCustomerLocation();
    } else {
      _stopLocationSharing();
    }
    _checkLockout();
    _autoAdvanceToStartCode();
  }

  /// Home Visit only: skips the "On My Way" and "I Have Arrived" screens.
  /// upcoming  -> PUT /artists/bookings/on_my_way/ -> PUT /artists/bookings/arrived/
  /// onTheWay  -> PUT /artists/bookings/arrived/
  /// The backend still gets both steps in the right order (it needs them to create the customer's start
  /// code); the artist just does not have to tap them. Only runs inside the allowed window (2 hours before
  /// the appointment) and only once — a failure stops here and shows a retry button instead of looping.
  Future<void> _autoAdvanceToStartCode() async {
    if (_isInSalon || _booking == null || _advancing || _advanceFailed) return;
    final stage = _stage;
    if (stage != JourneyStage.upcoming && stage != JourneyStage.onTheWay) return;
    if (stage == JourneyStage.upcoming && !widget.slot.isWithinUpcomingWindow) return;
    setState(() => _advancing = true);
    try {
      if (stage == JourneyStage.upcoming) {
        final b = await ServiceLocator.bookingJourneyService.markOnMyWay(_bookingId);
        if (!mounted) return;
        setState(() => _booking = b);
      }
      final arrived = await ServiceLocator.bookingJourneyService.markArrived(_bookingId);
      if (!mounted) return;
      setState(() {
        _booking = arrived;
        _advancing = false;
      });
      widget.onRefresh?.call();
      _afterBookingChanged(); // now `arrived`: location sharing + code entry
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _advancing = false;
        _advanceFailed = true; // set BEFORE handling the error so a reload cannot start this again
      });
      await _handleJourneyError(e);
    }
  }

  /// Retry button after a failed [_autoAdvanceToStartCode].
  void _retryAdvance() {
    setState(() => _advanceFailed = false);
    _autoAdvanceToStartCode();
  }

  /// Checks whether the completion code was already requested (artist tapped "Complete Service").
  Future<void> _refreshCompletionRequested() async {
    final requested = await ServiceLocator.bookingJourneyService.isCompletionRequested(_bookingId);
    if (mounted && requested != _completionRequested) setState(() => _completionRequested = requested);
  }

  /// Checks whether the Start Service code was already requested (In-Salon: artist tapped "Start Service").
  Future<void> _refreshStartRequested() async {
    final requested = await ServiceLocator.bookingJourneyService.isStartRequested(_bookingId);
    if (mounted && requested != _startRequested) {
      setState(() => _startRequested = requested);
      _checkLockout();
    }
  }

  /// Checks whether this booking's customer review was already given.
  Future<void> _refreshCustomerReviewed() async {
    final reviewed = await ReviewCustomerScreen.isReviewed(_bookingId);
    if (mounted && reviewed != _customerReviewed) setState(() => _customerReviewed = reviewed);
  }

  /// Opens the review screen. When the review was submitted, this Journey
  /// screen is closed too, so the artist lands back on the bookings list
  /// instead of on a finished journey.
  Future<void> _openReview() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ReviewCustomerScreen(bookingId: _bookingId, customerName: widget.slot.client),
    ));
    final reviewed = await ReviewCustomerScreen.isReviewed(_bookingId);
    if (!mounted) return;
    if (reviewed) {
      widget.onRefresh?.call();
      Navigator.of(context).pop();
    }
  }

  /// Artist taps "Complete Service" → backend creates the Completion PIN and notifies the customer.
  /// Tapping again re-sends the notification (same PIN), at most once a minute.
  /// API: bookingJourneyService.requestCompletionPin → PUT /artists/bookings/completion_pin/request/
  Future<void> _submitRequestCompletion() async {
    // Advance (20%) booking: ask "Did you receive ₹… ?" (Yes / No) before the photo and the code.
    final summary = _booking?.paymentSummary;
    if (summary != null && summary.needsAnswer) {
      final received = await askBalanceReceived(context, summary);
      if (received == null || !mounted) return;
      setState(() => _busy = true);
      try {
        final updated = await ServiceLocator.bookingJourneyService.confirmBalance(_bookingId, received: received);
        if (!mounted) return;
        setState(() => _booking = updated);
      } catch (e) {
        await _handleJourneyError(e);
        if (mounted) setState(() => _busy = false);
        return;
      }
      if (mounted) setState(() => _busy = false);
    }
    // The photo of the finished service comes first: without it the server refuses the completion code.
    if (!_hasCompletionPhoto) {
      final uploaded = await _takeCompletionPhoto();
      if (!uploaded) return;
    }
    setState(() => _busy = true);
    try {
      await ServiceLocator.bookingJourneyService.requestCompletionPin(_bookingId);
      if (!mounted) return;
      setState(() => _completionRequested = true);
      AppFeedback.showSuccess(context, 'Code Sent To The Customer — Ask Them To Read It Out');
    } catch (e) {
      await _handleJourneyError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Opens the CAMERA (never the gallery), then uploads the photo of the finished service.
  /// The original photo is sent as it is — the server shrinks it. Returns true when a photo is on the server.
  /// API: bookingJourneyService.uploadCompletionProof → PUT /artists/bookings/completion_proof/upload/
  Future<bool> _takeCompletionPhoto() async {
    final XFile? shot;
    try {
      shot = await ImagePicker().pickImage(source: ImageSource.camera);
    } catch (e) {
      if (mounted) AppFeedback.showError(context, e);
      return false;
    }
    if (shot == null || !mounted) return false;
    setState(() => _busy = true);
    try {
      final booking = await ServiceLocator.bookingJourneyService.uploadCompletionProof(_bookingId, shot);
      if (!mounted) return false;
      setState(() => _booking = booking);
      AppFeedback.showSuccess(context, 'Photo Saved');
      return booking.completionProof != null;
    } catch (e) {
      await _handleJourneyError(e);
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Loads customer location.
  /// Address comes inside the booking (GET /artists/bookings/get/) — artists cannot call /users/address/get/.
  Future<void> _loadCustomerLocation() async {
    final booking = _booking;
    final address = booking?.address;
    final addressId = booking?.addressId ?? address?.addressId;
    if (booking == null || address == null || addressId == null) return;
    if (_geocodedForAddressId == addressId && _customerLatLng != null) return;
    try {
      final latLng = await geocoder.AddressGeocoder.forAddress(address);
      if (!mounted) return;
      setState(() {
        _customerLatLng = latLng;
        _geocodedForAddressId = addressId;
      });
    } catch (_) {
    }
  }

  /// Starts location sharing.
  void _startLocationSharing() {
    final token = AppSession.instance.accessToken;
    if (token != null) _tracking.connect(_bookingId, token);
    _positionSub?.cancel();
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 15),
    ).listen(
          (pos) {
        _tracking.sendLocation(pos.latitude, pos.longitude);
        _firestoreLocation.pushLocation(_bookingId, pos.latitude, pos.longitude);
        if (mounted) {
          setState(() {
            _myLat = pos.latitude;
            _myLng = pos.longitude;
          });
        }
      },
      onError: (_) {
      },
    );
  }

  /// Stops location sharing.
  void _stopLocationSharing() {
    _positionSub?.cancel();
    _positionSub = null;
    _tracking.close();
    _firestoreLocation.stopSharing(_bookingId);
  }

  /// Live distance km.
  double? get _liveDistanceKm {
    final customer = _customerLatLng;
    if (_myLat == null || _myLng == null || customer == null) return null;
    return distanceKm(lat1: _myLat!, lng1: _myLng!, lat2: customer.lat, lng2: customer.lng);
  }

  /// Checks lockout.
  /// API: bookingJourneyService.lockoutRemaining
  Future<void> _checkLockout() async {
    final key = _stageCredentialKey;
    _lockTicker?.cancel();
    if (key == null) {
      if (mounted) setState(() { _lockRemaining = null; _lockedStageKey = null; });
      return;
    }
    // API call: bookingJourneyService.lockoutRemaining
    final remaining = await ServiceLocator.bookingJourneyService.lockoutRemaining(_bookingId, key);
    if (!mounted) return;
    setState(() { _lockRemaining = remaining; _lockedStageKey = key; });
    if (remaining != null) {
      _lockTicker = Timer.periodic(const Duration(seconds: 1), (t) {
        final left = _lockRemaining;
        if (left == null || left.inSeconds <= 1) {
          t.cancel();
          if (mounted) setState(() => _lockRemaining = null);
          return;
        }
        if (mounted) setState(() => _lockRemaining = left - const Duration(seconds: 1));
      });
    }
  }

  /// Returns true if locked.
  bool get _isLocked => _lockRemaining != null && _lockedStageKey == _stageCredentialKey;

  /// Formats lock.
  String _formatLock(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// Friendly reason.
  String _friendlyReason(String reason) {
    switch (reason) {
      case 'on_my_way_too_early':
        return 'Not Yet — Come Back Closer To The Appointment.';
      case 'on_my_way_not_allowed':
      case 'arrived_not_allowed':
      case 'start_pin_verify_not_allowed':
      case 'completion_pin_verify_not_allowed':
        return "This Booking's Status Changed — Refreshing.";
      case 'booking_not_found':
        return "Couldn't Find This Booking — Refreshing.";
      case 'otp_invalid':
        return "That Code Doesn't Match — Check The Notification You Were Sent.";
      case 'start_pin_invalid':
      case 'completion_pin_invalid':
        return "That Code Doesn't Match — Ask The Customer To Double Check It.";
      case 'account_locked':
        return 'Too Many Wrong Attempts. Locked For A While — Try Again Later.';
      default:
        return AppFeedback.friendlyMessage(reason);
    }
  }

  /// Reason means state changed.
  bool _reasonMeansStateChanged(String reason) =>
      reason.endsWith('_not_allowed') || reason.endsWith('_not_found');

  /// Handles journey error.
  Future<void> _handleJourneyError(Object e) async {
    if (e is JourneyReasonError) {
      AppFeedback.showWarning(context, _friendlyReason(e.reason));
      if (e.reason == 'account_locked') {
        await _checkLockout();
      } else if (_reasonMeansStateChanged(e.reason)) {
        await _load();
      }
      return;
    }
    AppFeedback.showError(context, e);
  }

  /// Submits on my way.
  /// API: bookingJourneyService.markOnMyWay → PUT /artists/bookings/on_my_way/
  Future<void> _submitOnMyWay() async {
    setState(() => _busy = true);
    try {
      // API call: bookingJourneyService.markOnMyWay → PUT /artists/bookings/on_my_way/
      final booking = await ServiceLocator.bookingJourneyService.markOnMyWay(_bookingId);
      if (!mounted) return;
      setState(() => _booking = booking);
      _afterBookingChanged();
      widget.onRefresh?.call();
    } catch (e) {
      await _handleJourneyError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Submits arrival — no code needed. The customer immediately gets their 4-digit start code.
  /// API: bookingJourneyService.markArrived → PUT /artists/bookings/arrived/
  Future<void> _submitArrival() async {
    setState(() => _busy = true);
    try {
      // API call: bookingJourneyService.markArrived → PUT /artists/bookings/arrived/
      final booking = await ServiceLocator.bookingJourneyService.markArrived(_bookingId);
      if (!mounted) return;
      setState(() => _booking = booking);
      _afterBookingChanged();
      widget.onRefresh?.call();
      AppFeedback.showSuccess(context, 'Arrival Confirmed — The Customer Got Their Start Code');
    } catch (e) {
      await _handleJourneyError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// In-Salon: the artist taps "Start Service" once the customer is there → the customer gets the 4-digit start code.
  /// Tapping again re-sends the notification (same PIN), at most once a minute.
  /// API: bookingJourneyService.requestStartPin → PUT /artists/bookings/start_pin/request/
  Future<void> _submitStartRequest() async {
    setState(() => _busy = true);
    try {
      await ServiceLocator.bookingJourneyService.requestStartPin(_bookingId);
      if (!mounted) return;
      setState(() => _startRequested = true);
      _afterBookingChanged();
      widget.onRefresh?.call();
      AppFeedback.showSuccess(context, 'Code Sent To The Customer — Ask Them To Read It Out');
    } catch (e) {
      await _handleJourneyError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Submits start PIN.
  /// API: bookingJourneyService.verifyStartPin → PUT /artists/bookings/start_pin/verify/
  Future<void> _submitStartPin() async {
    final pin = _pinController.text.trim();
    if (pin.length != 4) {
      AppFeedback.showWarning(context, 'Enter The 4-digit Code The Customer Gave You');
      return;
    }
    setState(() => _busy = true);
    try {
      // API call: bookingJourneyService.verifyStartPin → PUT /artists/bookings/start_pin/verify/
      final booking = await ServiceLocator.bookingJourneyService.verifyStartPin(_bookingId, pin);
      if (!mounted) return;
      _pinController.clear();
      setState(() {
        _booking = booking;
        _startRequested = false;
      });
      _afterBookingChanged();
      widget.onRefresh?.call();
      AppFeedback.showSuccess(context, 'Service Started!');
    } catch (e) {
      if (e is JourneyReasonError && e.reason.toLowerCase().contains('request the start service pin')) {
        // The server says the code was never requested → show the "Start Service" button again.
        await ServiceLocator.bookingJourneyService.clearStartRequested(_bookingId);
        if (mounted) setState(() => _startRequested = false);
        if (mounted) AppFeedback.showWarning(context, 'Tap "Start Service" First — The Customer Needs The Code.');
        return;
      }
      await _handleJourneyError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Submits completion PIN.
  /// API: bookingJourneyService.verifyCompletionPin → PUT /artists/bookings/completion_pin/verify/
  Future<void> _submitCompletionPin() async {
    final pin = _pinController.text.trim();
    if (pin.length != 4) {
      AppFeedback.showWarning(context, 'Enter The 4-digit Code The Customer Gave You');
      return;
    }
    setState(() => _busy = true);
    try {
      // API call: bookingJourneyService.verifyCompletionPin → PUT /artists/bookings/completion_pin/verify/
      final booking = await ServiceLocator.bookingJourneyService.verifyCompletionPin(_bookingId, pin);
      if (!mounted) return;
      _pinController.clear();
      setState(() => _booking = booking);
      _afterBookingChanged();
      widget.onRefresh?.call();
      AppFeedback.showSuccess(context, 'Booking Completed!');
    } catch (e) {
      if (e is JourneyReasonError && e.reason.toLowerCase().contains('request the completion pin')) {
        // The server says the code was never requested → show the "Complete Service" button again.
        await ServiceLocator.bookingJourneyService.clearCompletionRequested(_bookingId);
        if (mounted) setState(() => _completionRequested = false);
        if (mounted) AppFeedback.showWarning(context, 'Tap "Complete Service" First — The Customer Needs The Code.');
        return;
      }
      await _handleJourneyError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Submits cancel.
  Future<void> _submitCancel() async {
    final reason = await showAiraCancelReasonDialog(context, clientName: widget.slot.client);
    if (reason == null) return;
    widget.onUpdateStatus(widget.slot, SlotStatus.cancelled, reason: reason);
    widget.onRefresh?.call();
    if (mounted) Navigator.of(context).pop();
  }

  /// Builds the UI.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AiraColors.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: Row(
                children: [
                  SunndariBackChip(onTap: () => Navigator.of(context).pop()),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Service Journey', style: AiraText.serif(fontSize: 19, fontWeight: FontWeight.w600))),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _loading || _booking == null
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4, color: AiraColors.rose))
                  : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  children: [
                    AiraCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.slot.client, style: AiraText.sans(fontSize: 15, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text('${widget.slot.service} · ${widget.slot.time}',
                              style: AiraText.sans(fontSize: 12.5, color: AiraColors.charcoalSoft)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    _stepper(_stage),
                    const SizedBox(height: 24),
                    ..._stageContent(_stage),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// UI piece: stepper.
  Widget _stepper(JourneyStage stage) {
    // The travel steps (On The Way / Arrived) are not shown: Start Code → Service Started → Complete.
    const labels = ['Start Code', 'Service Started', 'Complete'];
    final activeIndex = switch (stage) {
      JourneyStage.arrived => 0,
      JourneyStage.inProgress => 1,
      JourneyStage.completed => 2,
      _ => -1,
    };
    return Row(
      children: List.generate(labels.length, (i) {
        final done = i <= activeIndex;
        return Expanded(
          child: Column(
            children: [
              Row(
                children: [
                  if (i > 0)
                    Expanded(
                      child: Container(height: 2, color: i - 1 < activeIndex ? AiraColors.rose : AiraColors.hair),
                    ),
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: done ? AiraColors.rose : AiraColors.hair,
                    ),
                  ),
                  if (i < labels.length - 1)
                    Expanded(
                      child: Container(height: 2, color: i < activeIndex ? AiraColors.rose : AiraColors.hair),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(labels[i],
                  textAlign: TextAlign.center,
                  style: AiraText.sans(fontSize: 10.5, color: done ? AiraColors.charcoal : AiraColors.charcoalSoft)),
            ],
          ),
        );
      }),
    );
  }

  /// Stage content.
  List<Widget> _stageContent(JourneyStage stage) {
    switch (stage) {
      case JourneyStage.upcoming:
        final within = widget.slot.isWithinUpcomingWindow;
        if (_isInSalon) {
          return [
            _infoCard(
              icon: Icons.storefront_outlined,
              title: 'Ready When The Customer Arrives',
              body: within
                  ? 'Once The Customer Is At Your Studio, Tap \"Start Service\". '
                  'They Then Get A 4-digit Start Code To Read Out To You.'
                  : 'You Can Start The Service From 2 Hours Before The Appointment.',
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Start Service',
              expand: true,
              onTap: _busy ? null : _submitStartRequest,
            ),
          ];
        }
        return _startingContent(within);

      case JourneyStage.missed:
        return [
          _infoCard(
            icon: Icons.event_busy_outlined,
            title: 'Booking Missed',
            body: _isInSalon
                ? 'The Scheduled Time Has Passed And This Service Was Never Started. '
                'It Can No Longer Be Started — Cancel It To Close It Out.'
                : 'The Scheduled Time Has Passed And This Service Was Never Started. '
                'It Can No Longer Be Started — Cancel It To Close It Out.',
          ),
          const SizedBox(height: 16),
          PrimaryButton(
            label: 'Cancel Booking',
            expand: true,
            background: AiraColors.errorText,
            onTap: _busy ? null : _submitCancel,
          ),
        ];

      case JourneyStage.onTheWay:
      // Not shown any more: the app marks Arrived by itself, then this becomes the code-entry screen.
        return _startingContent(true);

      case JourneyStage.arrived:
        if (_isInSalon) {
          return [
            _infoCard(
              icon: Icons.mark_email_read_outlined,
              title: 'Code Sent To Customer',
              body: 'The Customer Now Has A 4-digit Start Code In Their App — Ask Them To Read It Out To Start The Service.',
            ),
            const SizedBox(height: 20),
            _codeEntryCard(
              title: 'Enter The Customer\'s Code',
              subtitle: 'They\'ll Read This Out Loud From Their App.',
              controller: _pinController,
              length: 4,
              buttonLabel: 'Start Service',
              onSubmit: _submitStartPin,
            ),
            Center(
              child: TextButton(
                onPressed: _busy ? null : _submitStartRequest,
                child: Text('Customer Didn\'t Get It? Resend Code',
                    style: AiraText.sans(fontSize: 12.5, fontWeight: FontWeight.w600, color: AiraColors.roseDeep)),
              ),
            ),
          ];
        }
        return [
          _infoCard(
            icon: Icons.hourglass_bottom,
            title: 'You Have Arrived',
            body: 'The Customer Now Has A 4-digit Start Code In Their App — Ask Them To Read It Out To Start The Service.',
          ),
          const SizedBox(height: 20),
          _codeEntryCard(
            title: 'Enter The Customer\'s Code',
            subtitle: 'They\'ll Read This Out Loud From Their App.',
            controller: _pinController,
            length: 4,
            buttonLabel: 'Start Service',
            onSubmit: _submitStartPin,
          ),
        ];

      case JourneyStage.inProgress:
        if (!_completionRequested) {
          return [
            if (_booking?.paymentSummary?.isAdvance == true) ...[
              PaymentSummaryCard(summary: _booking!.paymentSummary!),
              const SizedBox(height: 16),
            ],
            _infoCard(
              icon: Icons.content_cut,
              title: 'Service In Progress',
              body: 'When You Have Finished, Take A Photo Of The Finished Service With Your Camera, Then Tap "Complete Service". '
                  'The Customer Then Gets A 4-digit Completion Code To Read Out To You.',
            ),
            if (_hasCompletionPhoto) ...[
              const SizedBox(height: 16),
              _completionPhotoCard(canRetake: true),
            ],
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Complete Service',
              expand: true,
              onTap: _busy ? null : _submitRequestCompletion,
            ),
          ];
        }
        return [
          _infoCard(
            icon: Icons.mark_email_read_outlined,
            title: 'Code Sent To Customer',
            body: 'The Customer Now Has A 4-digit Completion Code In Their App — Ask Them To Read It Out.',
          ),
          const SizedBox(height: 20),
          _codeEntryCard(
            title: 'Enter The Completion Code',
            subtitle: 'They\'ll Read This Out Loud From Their App.',
            controller: _pinController,
            length: 4,
            buttonLabel: 'Mark Complete',
            onSubmit: _submitCompletionPin,
          ),
          Center(
            child: TextButton(
              onPressed: _busy ? null : _submitRequestCompletion,
              child: Text('Customer Didn\'t Get It? Resend Code',
                  style: AiraText.sans(fontSize: 12.5, fontWeight: FontWeight.w600, color: AiraColors.roseDeep)),
            ),
          ),
        ];

      case JourneyStage.completed:
      // Review already given → no "Review Customer" button any more, just a
      // way back to the bookings list.
        if (_customerReviewed) {
          return [
            _infoCard(
              icon: Icons.check_circle_outline,
              title: 'Booking Completed',
              body: 'Nicely Done. Your Review For The Customer Is Saved.',
            ),
            if (_hasCompletionPhoto) ...[
              const SizedBox(height: 16),
              _completionPhotoCard(canRetake: false),
            ],
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Back To Bookings',
              expand: true,
              onTap: () => Navigator.of(context).pop(),
            ),
          ];
        }
        return [
          _infoCard(
            icon: Icons.check_circle_outline,
            title: 'Booking Completed',
            body: 'Nicely Done. Leave A Quick Review For The Customer While It\'s Fresh.',
          ),
          if (_hasCompletionPhoto) ...[
            const SizedBox(height: 16),
            _completionPhotoCard(canRetake: false),
          ],
          const SizedBox(height: 16),
          PrimaryButton(
            label: 'Review Customer',
            expand: true,
            // Opens ReviewCustomerScreen; after a submitted review this screen closes too.
            onTap: _openReview,
          ),
        ];
    }
  }

  /// Home Visit, before the start code exists: no On My Way / Arrived screens, just a short
  /// "getting ready" state (or the reason it cannot start yet, with a retry button).
  List<Widget> _startingContent(bool within) {
    if (_advanceFailed) {
      return [
        _infoCard(
          icon: Icons.error_outline,
          title: 'Could Not Get The Start Code',
          body: 'Please Check Your Internet And Try Again. If It Keeps Failing, Pull Down To Refresh.',
        ),
        const SizedBox(height: 16),
        PrimaryButton(label: 'Try Again', expand: true, onTap: _busy ? null : _retryAdvance),
      ];
    }
    if (!within) {
      return [
        _infoCard(
          icon: Icons.schedule,
          title: 'Not Time Yet',
          body: 'You Can Start The Service From 2 Hours Before The Appointment.',
        ),
      ];
    }
    return [
      _infoCard(
        icon: Icons.mark_email_read_outlined,
        title: 'Getting The Start Code Ready',
        body: 'The Customer Is Being Sent A 4-digit Start Code — Ask Them To Read It Out To You.',
      ),
      const SizedBox(height: 20),
      const Center(child: CircularProgressIndicator(strokeWidth: 2.4, color: AiraColors.rose)),
    ];
  }

  /// UI piece: the photo of the finished service (private — shown with the Bearer header).
  /// While the service is in progress the artist can take it again; the new photo replaces the old one.
  Widget _completionPhotoCard({required bool canRetake}) {
    final proof = _booking?.completionProof;
    if (proof == null) return const SizedBox.shrink();
    return AiraCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CompletionProofImage(proof: proof, width: 64, height: 64),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Photo Of The Finished Service',
                style: AiraText.sans(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          if (canRetake)
            TextButton(
              onPressed: _busy ? null : _takeCompletionPhoto,
              child: Text('Retake',
                  style: AiraText.sans(fontSize: 12.5, fontWeight: FontWeight.w600, color: AiraColors.roseDeep)),
            ),
        ],
      ),
    );
  }

  /// UI piece: code entry card.
  Widget _codeEntryCard({
    required String title,
    required String subtitle,
    required TextEditingController controller,
    required int length,
    required String buttonLabel,
    required VoidCallback onSubmit,
  }) {
    final locked = _isLocked;
    return AiraCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Text(title, style: AiraText.sans(fontSize: 13.5, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(subtitle, style: AiraText.sans(fontSize: 12, color: AiraColors.charcoalSoft), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          if (locked) ...[
            Icon(Icons.lock_clock_outlined, color: AiraColors.charcoalSoft, size: 28),
            const SizedBox(height: 8),
            Text(
              'Locked — Try Again In ${_formatLock(_lockRemaining!)}',
              style: AiraText.sans(fontSize: 13, fontWeight: FontWeight.w600, color: AiraColors.charcoalSoft),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Too Many Wrong Attempts On This Code.',
              style: AiraText.sans(fontSize: 11.5, color: AiraColors.charcoalSoft),
              textAlign: TextAlign.center,
            ),
          ] else ...[
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(length)],
              maxLength: length,
              textAlign: TextAlign.center,
              style: AiraText.serif(fontSize: 24, fontWeight: FontWeight.w600).copyWith(letterSpacing: 6),
              decoration: InputDecoration(
                counterText: '',
                hintText: '•' * length,
                filled: true,
                fillColor: AiraColors.card,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AiraColors.hair)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AiraColors.hair)),
              ),
            ),
            const SizedBox(height: 16),
            PrimaryButton(label: buttonLabel, expand: true, onTap: _busy ? null : onSubmit),
          ],
        ],
      ),
    );
  }

  /// UI piece: info card.
  Widget _infoCard({required IconData icon, required String title, required String body}) {
    return AiraCard(
      padding: const EdgeInsets.all(16),
      borderColor: AiraColors.goldSoft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: AiraColors.goldSoft, borderRadius: BorderRadius.circular(16)),
            child: Icon(icon, size: 18, color: AiraColors.roseDeep),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AiraText.sans(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(body, style: AiraText.sans(fontSize: 12.5, color: AiraColors.charcoalSoft, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}