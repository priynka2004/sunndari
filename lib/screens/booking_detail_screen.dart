// FILE: screens/booking_detail_screen.dart
// SCREEN: Booking Detail — one booking: customer, package, location, payment, status + actions (accept, journey, reschedule, chat, help).

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:android_intent_plus/android_intent.dart';

import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../models/models.dart';
import '../models/booking/booking.dart';
import '../models/artist/package.dart';
import '../models/core/status_item.dart';
import '../models/core/location_type.dart';
import '../models/user/customer_address.dart';
import '../helper/booking_stats.dart';
import '../utils/service_locator.dart';
import '../widgets/journey_action_button.dart';
import 'chat_screen.dart';
import 'change_booking_screen.dart';
import 'reschedule_request_screen.dart';
import '../models/booking/booking_reschedule.dart';
import '../widgets/reschedule_widgets.dart';
import 'booking_help_screen.dart';
import '../models/booking/booking_journey.dart';
import '../utils/artist_page_data.dart';
import '../utils/app_feedback.dart';
import '../api/booking_journey_service.dart' show JourneyReasonError;
import '../utils/address_geocoder.dart' as geocoder;

/// SCREEN: Booking Detail — one booking: customer, package, location, payment, status + actions (accept, journey, reschedule, chat, help).
class BookingDetailScreen extends StatefulWidget {
  final int bookingId;
  final void Function(BookingSlot slot, SlotStatus next, {String? reason})? onUpdateStatus;
  final BookingSlot? slot;
  final List<StatusItem> statuses;
  final VoidCallback? onRefresh;

  const BookingDetailScreen({
    super.key,
    required this.bookingId,
    this.slot,
    this.onUpdateStatus,
    this.statuses = const [],
    this.onRefresh,
  });

  @override
  State<BookingDetailScreen> createState() => _BookingDetailScreenState();
}

/// State of [BookingDetailScreen] — holds the screen data and logic.
class _BookingDetailScreenState extends State<BookingDetailScreen> {
  bool _loading = true;
  String? _error;
  Booking? _booking;
  Package? _package;
  double _commission = 0;
  List<AddOn> _addOns = [];
  String? _customerName;
  List<StatusItem> _statuses = const [];
  StreamSubscription<Booking?>? _liveSub;
  BookingReschedule? _reschedule;

  LocationType? _locationType;
  CustomerAddress? _address;
  List<StatusItem> _paymentStatuses = const [];
  bool _completionRequested = false;
  bool _pinBusy = false;

  // OTP Input के लिए Variables
  final TextEditingController _otpController = TextEditingController();
  final FocusNode _otpFocusNode = FocusNode();

  /// Runs once when the screen opens; starts: _loadExtras(), _loadReschedule(), _load(), _listenLive().
  @override
  void initState() {
    super.initState();
    // Focus change होने पर box का border कलर बदलने के लिए
    _otpFocusNode.addListener(() {
      setState(() {});
    });
    _loadExtras();
    _loadReschedule();
    _statuses = widget.statuses;
    _load();
    _listenLive();
  }

  /// Frees controllers / listeners when the screen closes.
  @override
  void dispose() {
    _otpController.dispose();
    _otpFocusNode.dispose();
    _liveSub?.cancel();
    super.dispose();
  }

  /// Listens to live.
  void _listenLive() {
    _liveSub = ServiceLocator.firestoreBookingService
        .bookingStream(widget.bookingId)
        .listen(
          (booking) {
        if (!mounted || booking == null) return;
        // Firestore only tells us "something changed". The API copy is the
        // source of truth, so re-read it instead of trusting the live doc
        // (a stale live doc was what kept showing the old stage).
        _refreshBooking();
      },
      onError: (_) {
      },
    );
  }

  /// Re-reads just the booking from the API (no loading spinner). Used after
  /// the journey screen changed something, so this screen never shows an old
  /// stage.
  Future<void> _refreshBooking() async {
    try {
      final fresh = await ServiceLocator.bookingService.getBooking(widget.bookingId);
      if (!mounted) return;
      setState(() => _booking = fresh);
    } catch (_) {
    }
  }

  /// Called by the journey button / journey screen after any step.
  void _onJourneyRefresh() {
    widget.onRefresh?.call();
    _refreshBooking();
  }

  /// Loads this screen's data.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final booking = await ServiceLocator.bookingService.getBooking(widget.bookingId);

      if (_statuses.isEmpty) {
        try {
          _statuses = await ServiceLocator.coreService.getBookingStatuses();
        } catch (_) {
        }
      }

      Package? pkg;
      try {
        pkg = await ServiceLocator.artistService.getPackage(booking.packageId);
      } catch (_) {
      }

      if (widget.slot == null || widget.slot!.client == 'Customer') {
        unawaited(_loadCustomerName(booking.customerId));
      }

      LocationType? locationType;
      try {
        locationType = await ServiceLocator.coreService.getLocationType(booking.locationTypeId);
      } catch (_) {
      }

      CustomerAddress? address;
      final addressId = booking.addressId;
      if (addressId != null) {
        try {
          address = await ServiceLocator.userService.getAddress(addressId);
        } catch (e) {
          if (kDebugMode) debugPrint('[booking] getAddress($addressId) failed: $e');
        }
      }

      List<StatusItem> paymentStatuses = const [];
      if (booking.paymentStatusId != null) {
        try {
          paymentStatuses = await ServiceLocator.coreService.getPaymentStatuses();
        } catch (_) {
        }
      }

      final completionRequested = await ServiceLocator.bookingJourneyService.isCompletionRequested(booking.bookingId);
      if (!mounted) return;
      setState(() {
        _completionRequested = completionRequested;
        _booking = booking;
        _package = pkg;
        _locationType = locationType;
        _address = address;
        _paymentStatuses = paymentStatuses;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        final msg = e.toString().replaceFirst('Exception: ', '');
        // The server hides unpaid bookings by answering "Booking not found".
        _error = msg.toLowerCase().contains('not found')
            ? 'This Booking Is Not Available — It May Be Waiting For The Customer\'s Payment.'
            : msg;
        _loading = false;
      });
    }
  }

  /// Loads customer name.
  Future<void> _loadCustomerName(int customerId) async {
    try {
      final profile = await ServiceLocator.userService.getProfile(customerId);
      if (!mounted || profile.name.trim().isEmpty) return;
      setState(() => _customerName = profile.name.trim());
    } catch (_) {
    }
  }

  /// Loads reschedule.
  Future<void> _loadReschedule() async {
    final r = await ServiceLocator.rescheduleService.get(widget.bookingId);
    if (mounted) setState(() => _reschedule = r);
  }

  /// Reschedule applied.
  bool get _rescheduleApplied => _reschedule?.status == RescheduleStatus.accepted;

  /// Reschedule pending.
  bool get _reschedulePending => _reschedule?.isPending ?? false;

  /// Applies status.
  Future<void> _applyStatus(BookingSlot slot, SlotStatus next, {String? reason}) async {
    final parent = widget.onUpdateStatus;
    if (parent != null) {
      parent(slot, next, reason: reason);
      return;
    }
    final apiStatus = switch (next) {
      SlotStatus.confirmed => BookingStatusEnum.confirmed,
      SlotStatus.inProgress => BookingStatusEnum.inProgress,
      SlotStatus.completed => BookingStatusEnum.completed,
      SlotStatus.cancelled => BookingStatusEnum.cancelled,
      SlotStatus.noShow => BookingStatusEnum.noShow,
      _ => BookingStatusEnum.confirmed,
    };
    try {
      await ServiceLocator.bookingService.updateBookingStatus(widget.bookingId, apiStatus, reason: reason);
      widget.onRefresh?.call();
      if (mounted) {
        AppFeedback.showSuccess(context, 'Booking Updated ✓');
        _load();
      }
    } catch (e) {
      if (mounted) AppFeedback.showError(context, e);
    }
  }

  /// Effective status.
  SlotStatus get _effectiveStatus {
    final booking = _booking;
    if (booking != null) {
      return BookingStats.mapStatus(booking.statusId, _statuses, cancelledBy: booking.cancelledBy);
    }
    return widget.slot?.status ?? SlotStatus.open;
  }

  /// Returns true if missed.
  bool get _isMissed =>
      _slotForCallback.isMissed &&
          (_effectiveStatus == SlotStatus.pending ||
              _effectiveStatus == SlotStatus.confirmed ||
              _effectiveStatus == SlotStatus.inProgress);

  /// Client name.
  String get _clientName {
    final slotName = widget.slot?.client;
    final isPlaceholder = slotName == null || slotName.isEmpty || slotName == 'Customer';
    if (!isPlaceholder) return slotName;
    return _customerName ?? 'Customer';
  }

  /// Package label.
  String get _packageLabel =>
      (_package?.name.trim().isNotEmpty ?? false)
          ? _package!.name.trim()
          : ((widget.slot?.service.isNotEmpty ?? false) && widget.slot!.service != 'Service'
          ? widget.slot!.service
          : 'Service');

  /// Status row label.
  String get _statusRowLabel {
    if (_isMissed) return 'Missed';
    if (_reschedulePending && _effectiveStatus == SlotStatus.confirmed) {
      return _reschedule!.fromCustomer ? 'Reschedule Request' : 'Reschedule Requested';
    }
    if (_effectiveStatus == SlotStatus.confirmed && _slotForCallback.isFutureDate) {
      return 'Upcoming';
    }
    return switch (_effectiveStatus) {
      SlotStatus.pending => 'New Request',
      SlotStatus.confirmed => 'Confirmed',
      SlotStatus.inProgress => 'In Progress',
      SlotStatus.completed => 'Completed',
      SlotStatus.cancelled => 'Cancelled',
      SlotStatus.noShow => 'No-show',
      _ => 'Open',
    };
  }

  /// Location label.
  String? get _locationLabel {
    final typeName = _locationType?.name;
    if (typeName == null) return null;
    final addr = _address;
    if (addr == null) return typeName;
    final line2 = (addr.addressLine2?.trim().isNotEmpty ?? false) ? ', ${addr.addressLine2}' : '';
    return '$typeName — ${addr.addressLine1}$line2, ${addr.city} ${addr.pinCode}';
  }

  /// Payment status label.
  String? get _paymentStatusLabel {
    final id = _booking?.paymentStatusId;
    if (id == null) return null;
    final match = _paymentStatuses.where((s) => s.statusId == id);
    if (match.isEmpty) return null;
    final name = match.first.name;
    return name.isEmpty ? null : name[0].toUpperCase() + name.substring(1);
  }

  /// Time label.
  String get _timeLabel {
    if (_rescheduleApplied) return RescheduleFmt.time(_reschedule!.newStart);
    if (widget.slot != null) return widget.slot!.time;
    final booking = _booking;
    return booking != null ? _formatTime(booking.startTime) : '—';
  }

  /// Slot for callback.
  BookingSlot get _slotForCallback {
    final base = widget.slot ??
        BookingSlot(
          bookingId: widget.bookingId,
          date: _booking?.bookingDate ?? '',
          time: _timeLabel,
          rawStartTime: _booking?.startTime,
          client: _clientName,
          service: _packageLabel,
          status: _effectiveStatus,
          amount: _booking?.totalAmount,
        );
    if (!_rescheduleApplied) return base;
    final n = _reschedule!.newStart;
    String two(int v) => v.toString().padLeft(2, '0');
    return BookingSlot(
      bookingId: base.bookingId,
      date: '${n.year}-${two(n.month)}-${two(n.day)}',
      time: RescheduleFmt.time(n),
      rawStartTime: '${two(n.hour)}:${two(n.minute)}',
      client: base.client,
      service: base.service,
      status: base.status,
      amount: base.amount,
    );
  }

  /// Formats time.
  String _formatTime(String startTime) {
    try {
      final parts = startTime.split(':');
      final h = int.parse(parts[0]);
      final m = parts.length > 1 ? parts[1] : '00';
      final suffix = h >= 12 ? 'PM' : 'AM';
      final h12 = h % 12 == 0 ? 12 : h % 12;
      return '$h12:$m $suffix';
    } catch (_) {
      return startTime;
    }
  }

  /// Loads extras.
  Future<void> _loadExtras() async {
    try {
      final p = await ServiceLocator.artistService.getProfile();
      _commission = p.commissionRate;
    } catch (_) {}
    try {
      _addOns = await ArtistPageLocal.addOns();
    } catch (_) {}
    if (mounted) setState(() {});
  }

  /// Formats date.
  String _formatDate(String iso) {
    try {
      final d = DateTime.parse(iso);
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${d.day} ${months[d.month - 1]} ${d.year}';
    } catch (_) {
      return iso;
    }
  }

  /// UI piece: section title.
  Widget _sectionTitle(String t) => Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 8),
    child: Text(t, style: AiraText.serif(fontSize: 18)),
  );

  /// Returns true if request.
  bool get _isRequest => _effectiveStatus == SlotStatus.pending;

  /// UI piece: status pill.
  Widget _statusPill(String text, Color bg, Color fg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
    child: Text(text, style: AiraText.sans(fontSize: 11.5, fontWeight: FontWeight.w700, color: fg)),
  );

  /// Booking length in minutes (end − start), or null if unknown.
  int? _bookingMinutes(Booking? b) {
    int? m(String? v) {
      final p = v?.split(':');
      if (p == null || p.length < 2) return null;
      final h = int.tryParse(p[0]), mi = int.tryParse(p[1]);
      return h == null || mi == null ? null : h * 60 + mi;
    }
    final st = m(b?.startTime), en = m(b?.endTime);
    return (st != null && en != null && en > st) ? en - st : null;
  }

  /// Opens change.
  Future<bool> _openChange({bool viaHelp = false}) async {
    if (_reschedulePending) {
      AppFeedback.showInfo(
        context,
        _reschedule!.fromCustomer
            ? 'Please Answer The Client’s Reschedule Request First'
            : 'A Reschedule Request Is Already Waiting For The Client',
      );
      return false;
    }
    final b = _booking;
    final currentStart = _booking?.startDateTime ?? widget.slot?.startDateTime ?? DateTime.now();
    final result = await Navigator.of(context).push<RescheduleRequest>(MaterialPageRoute(
      builder: (_) => ChangeBookingScreen(
        bookingId: widget.bookingId,
        clientName: _clientName,
        currentStart: _rescheduleApplied ? _reschedule!.newStart : currentStart,
        durationMinutes: _bookingMinutes(b),
        serviceName: _packageLabel,
        dateLabel: b != null ? _formatDate(b.bookingDate) : (widget.slot?.date ?? '—'),
        timeLabel: _timeLabel,
        venueLabel: _locationLabel ?? 'Client Location',
        onCancelBooking: () async {
          final reason = await showAiraCancelReasonDialog(context, clientName: _clientName);
          if (reason == null) return;
          _applyStatus(_slotForCallback, SlotStatus.cancelled, reason: reason);
          if (!mounted) return;
          final nav = Navigator.of(context)..pop();
          if (viaHelp) nav.pop();
          nav.pop();
        },
      ),
    ));
    await _loadReschedule();
    widget.onRefresh?.call();
    return result != null;
  }

  /// Opens reschedule request.
  Future<void> _openRescheduleRequest() async {
    final r = _reschedule;
    if (r == null) return;
    final answered = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => RescheduleRequestScreen(
        request: r,
        clientName: _clientName,
        serviceName: _packageLabel,
      ),
    ));
    await _loadReschedule();
    if (answered == true) widget.onRefresh?.call();
  }

  /// Withdraws reschedule.
  Future<void> _withdrawReschedule() async {
    final r = _reschedule;
    if (r == null) return;
    try {
      await ServiceLocator.rescheduleService.withdraw(r);
      await _loadReschedule();
      if (mounted) AppFeedback.showInfo(context, 'Reschedule Request Withdrawn');
    } catch (e) {
      if (mounted) AppFeedback.showError(context, e);
    }
  }

  /// Dismisses reschedule.
  Future<void> _dismissReschedule() async {
    await ServiceLocator.rescheduleService.clear(widget.bookingId);
    await _loadReschedule();
  }

  /// UI piece: reschedule card.
  Widget _rescheduleCard() {
    final r = _reschedule;
    if (r == null || r.status == RescheduleStatus.withdrawn) return const SizedBox.shrink();

    Widget banner(Color bg, Color border, IconData icon, Color iconColor, String text, {bool dismiss = true}) => Padding(
      padding: const EdgeInsets.only(top: 12),
      child: AiraCard(
        padding: const EdgeInsets.all(12),
        backgroundColor: bg,
        borderColor: border,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: iconColor),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: AiraText.sans(fontSize: 12.5, color: AiraColors.charcoal, height: 1.35))),
            if (dismiss)
              GestureDetector(
                onTap: _dismissReschedule,
                child: const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.close_rounded, size: 18, color: AiraColors.charcoalSoft),
                ),
              ),
          ],
        ),
      ),
    );

    switch (r.status) {
      case RescheduleStatus.accepted:
        return banner(const Color(0xFFE3F5EA), AiraColors.success, Icons.check_circle_outline_rounded, AiraColors.success,
            'Rescheduled — This Booking Is Now On ${RescheduleFmt.dateTime(r.newStart)}.');
      case RescheduleStatus.declined:
        return banner(AiraColors.errorBg, AiraColors.errorText, Icons.event_busy_outlined, AiraColors.errorText,
            r.fromCustomer
                ? 'You Declined The Reschedule Request. The Booking Stays On ${RescheduleFmt.dateTime(r.oldStart)}.'
                : 'The Client Declined Your Reschedule Request. The Booking Stays On ${RescheduleFmt.dateTime(r.oldStart)}.');
      case RescheduleStatus.counterProposed:
        return banner(const Color(0xFFFFF6DD), AiraColors.warn, Icons.schedule_send_outlined, AiraColors.warn,
            'You Suggested ${RescheduleFmt.dateTime(r.suggestedStart ?? r.newStart)}. Waiting For The Client To Respond.');
      case RescheduleStatus.requested:
        break;
      case RescheduleStatus.withdrawn:
        return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: AiraCard(
        padding: const EdgeInsets.all(14),
        borderColor: AiraColors.pinkBorder,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SunndariIconBubble(icon: Icons.event_repeat_outlined, size: 38),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(r.fromCustomer ? 'Reschedule Request' : 'Reschedule Requested',
                      style: AiraText.serif(fontSize: 17, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            RescheduleCompareCard(
              oldStart: r.oldStart,
              newStart: r.newStart,
              oldLabel: 'Old Date & Time',
              newLabel: r.fromCustomer ? 'New Requested' : 'You Requested',
            ),
            const SizedBox(height: 12),
            if (r.fromCustomer)
              PrimaryButton(
                  label: 'Review Reschedule Request', icon: Icons.rate_review_outlined, expand: true, small: true, onTap: _openRescheduleRequest)
            else ...[
              Text('Waiting For The Client To Answer (They Have 24 Hours). Your Booking Stays At The Old Time Until Then.',
                  style: AiraText.sans(fontSize: 12.5, color: AiraColors.charcoalSoft, height: 1.35)),
              const SizedBox(height: 10),
              GhostButton(label: 'Withdraw Request', icon: Icons.undo_rounded, small: true, expand: true, onTap: _withdrawReschedule),
            ],
          ],
        ),
      ),
    );
  }

  /// Date text.
  String get _dateText => _rescheduleApplied
      ? RescheduleFmt.date(_reschedule!.newStart)
      : (_booking != null ? _formatDate(_booking!.bookingDate) : (widget.slot?.date ?? '—'));

  /// Duration minutes.
  int get _durationMinutes => _package?.durationMinutes ?? 0;

  /// Reserved window.
  String? get _reservedWindow {
    final b = _booking;
    if (b == null) return null;
    String fmt(DateTime d) {
      final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
      return '$h:${d.minute.toString().padLeft(2, '0')}';
    }

    final start = b.startDateTime;
    if (start == null) return null;
    DateTime end = start.add(Duration(minutes: _durationMinutes));
    if (b.endTime != null && b.endTime!.contains(':')) {
      try {
        final p = b.endTime!.split(':').map(int.parse).toList();
        end = DateTime(start.year, start.month, start.day, p[0], p[1]);
      } catch (_) {}
    }
    return '${fmt(start)} ${start.hour >= 12 ? 'PM' : 'AM'} – ${fmt(end)} ${end.hour >= 12 ? 'PM' : 'AM'}';
  }

  /// Applicable add ons.
  List<AddOn> get _applicableAddOns {
    final id = _package?.packageId;
    if (id == null) return const [];
    return _addOns.where((a) => a.packageIds.contains(id)).toList();
  }

  /// UI piece: card.
  Widget _card(List<Widget> children, {EdgeInsets? padding}) => AiraCard(
    padding: padding ?? const EdgeInsets.fromLTRB(14, 8, 14, 8),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
  );

  /// UI piece: row item.
  Widget _rowItem(IconData icon, String label, String value, {String? sub, Widget? trailing, bool last = false}) => Container(
    padding: const EdgeInsets.symmetric(vertical: 11),
    decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: AiraColors.hair))),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SunndariIconBubble(icon: icon, size: 38),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AiraText.sans(fontSize: 11.5, color: AiraColors.charcoalSoft)),
              const SizedBox(height: 1),
              Text(value, style: AiraText.sans(fontSize: 14.5, fontWeight: FontWeight.w800, color: AiraColors.roseDeep)),
              if (sub != null) Text(sub, style: AiraText.sans(fontSize: 11.5, color: AiraColors.charcoalSoft)),
            ],
          ),
        ),
        if (trailing != null) trailing,
      ],
    ),
  );

  /// Gets directions — opens Google Maps with the exact customer location.
  Future<void> _getDirections() async {
    final addr = _address;

    // No customer address on this booking (e.g. "In - Salon": the client comes to you).
    // Never send the venue-type label ("In - Salon") to Maps — it shows up as a bare title with no place.
    if (addr == null) {
      AppFeedback.showInfo(
        context,
        _locationType != null
            ? 'No Client Address For This Booking (${_locationType!.name}) — Nothing To Navigate To'
            : 'The Client Address Is Not Available Yet',
      );
      return;
    }

    AppFeedback.showInfo(context, 'Opening Google Maps…');
    final point = await geocoder.AddressGeocoder.forAddress(addr);
    if (!mounted) return;

    final label = addr.fullText;
    try {
      if (Platform.isAndroid) {
        if (point != null) {
          // Exact pin + turn-by-turn route from the artist's current location.
          final dest = '${point.lat},${point.lng}';
          try {
            await AndroidIntent(
              action: 'action_view',
              data: 'google.navigation:q=$dest&mode=d',
              package: 'com.google.android.apps.maps',
            ).launch();
          } catch (_) {
            await AndroidIntent(
              action: 'action_view',
              data: 'geo:$dest?q=$dest(${Uri.encodeComponent(_clientName)})',
            ).launch();
          }
        } else {
          // Could not find coordinates → search by the full address text.
          await AndroidIntent(
            action: 'action_view',
            data: 'geo:0,0?q=${Uri.encodeComponent(label)}',
          ).launch();
        }
      } else {
        AppFeedback.showInfo(context, label);
      }
    } catch (_) {
      if (mounted) AppFeedback.showInfo(context, label);
    }
  }

  JourneyStage? get _stage {
    final b = _booking;
    if (b == null) return null;
    return JourneyStage.fromBooking(b, _effectiveStatus);
  }

  /// Stage index.
  int get _stageIndex => switch (_stage) {
    JourneyStage.onTheWay => 1,
    JourneyStage.arrived => 2,
    JourneyStage.inProgress => 3,
    JourneyStage.completed => 4,
    _ => 0,
  };

  /// UI piece: progress.
  Widget _progress() {
    const steps = [
      ('Confirmed', 'Booking Accepted. You’re All Set!'),
      ('On The Way', 'Tap The Button Below When You Are On The Way.'),
      ('Arrived', 'Mark When You Reach The Client’s Venue.'),
      ('Start Service', 'Enter The Service Code To Begin.'),
      ('Completed', 'Mark When The Service Is Completed.'),
    ];
    final cur = _stage == JourneyStage.completed ? steps.length : _stageIndex;
    return Column(
      children: [
        for (var i = 0; i < steps.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < cur ? AiraColors.roseDeep : Colors.white,
                        border: Border.all(color: i <= cur ? AiraColors.roseDeep : AiraColors.charcoalSoft.withOpacity(0.5), width: i == cur ? 5 : 1.5),
                      ),
                      child: i < cur ? const Icon(Icons.check_rounded, size: 14, color: Colors.white) : null,
                    ),
                    if (i != steps.length - 1)
                      Expanded(child: Container(width: 1.5, margin: const EdgeInsets.symmetric(vertical: 2), color: i < cur ? AiraColors.roseDeep : AiraColors.pinkBorder)),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    margin: EdgeInsets.only(bottom: i == steps.length - 1 ? 0 : 6),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: i == cur ? AiraColors.blush : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(steps[i].$1, style: AiraText.sans(fontSize: 13.5, fontWeight: FontWeight.w800, color: AiraColors.roseDeep)),
                        Text(steps[i].$2, style: AiraText.sans(fontSize: 11.5, color: AiraColors.charcoalSoft)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }


  /// When "On My Way" unlocks (2 hours before the appointment), e.g. "19 Oct, 3:00 PM".
  String? get _onMyWayUnlockLabel {
    final start = _booking?.startDateTime;
    if (start == null) return null;
    final t = start.subtract(const Duration(hours: 2));
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    return '${t.day} ${months[t.month - 1]}, $h:$m ${t.hour >= 12 ? 'PM' : 'AM'}';
  }

  /// Artist taps "Complete Service" → the customer gets the 4-digit completion code.
  /// Tapping again re-sends it (once a minute at most).
  /// API: PUT /artists/bookings/completion_pin/request/
  Future<void> _requestCompletion() async {
    setState(() => _pinBusy = true);
    try {
      await ServiceLocator.bookingJourneyService.requestCompletionPin(widget.bookingId);
      if (!mounted) return;
      setState(() => _completionRequested = true);
      AppFeedback.showSuccess(context, 'Code Sent To The Customer — Ask Them To Read It Out');
    } catch (e) {
      if (!mounted) return;
      AppFeedback.showError(context, e is JourneyReasonError ? AppFeedback.friendlyMessage(e.reason) : e);
    } finally {
      if (mounted) setState(() => _pinBusy = false);
    }
  }

  /// Verifies the 4-digit code the customer reads out (start code, then completion code).
  Future<void> _verifyCode() async {
    final code = _otpController.text.trim();
    if (code.length != 4) {
      AppFeedback.showError(context, 'Please Enter The 4-digit Code');
      return;
    }
    final stageNow = _stage;
    setState(() => _pinBusy = true);
    try {
      final svc = ServiceLocator.bookingJourneyService;
      final Booking b = stageNow == JourneyStage.inProgress
          ? await svc.verifyCompletionPin(widget.bookingId, code)
          : await svc.verifyStartPin(widget.bookingId, code);
      if (!mounted) return;
      _otpController.clear();
      if (stageNow == JourneyStage.inProgress) {
        await ServiceLocator.bookingJourneyService.clearCompletionRequested(widget.bookingId);
        _completionRequested = false;
      }
      setState(() => _booking = b);
      widget.onRefresh?.call();
      AppFeedback.showSuccess(context, stageNow == JourneyStage.inProgress ? 'Booking Completed!' : 'Service Started!');
    } catch (e) {
      if (!mounted) return;
      if (e is JourneyReasonError) {
        if (e.reason.toLowerCase().contains('request the completion pin')) {
          // Server says the code was never requested → show the "Complete Service" button again.
          await ServiceLocator.bookingJourneyService.clearCompletionRequested(widget.bookingId);
          if (mounted) setState(() => _completionRequested = false);
          if (mounted) AppFeedback.showWarning(context, 'Tap "Complete Service" First — The Customer Needs The Code.');
        } else {
          AppFeedback.showWarning(
            context,
            e.reason == 'account_locked'
                ? 'Too Many Wrong Attempts. Locked For A While — Try Again Later.'
                : "That Code Doesn't Match — Ask The Customer To Double Check It.",
          );
        }
      } else {
        AppFeedback.showError(context, e);
      }
    } finally {
      if (mounted) setState(() => _pinBusy = false);
    }
  }

  /// UI piece: code card.
  ///  - before arrival  → only a short explanation (nothing to enter yet)
  ///  - arrived         → 4-digit start code the customer reads out
  ///  - in progress     → "Complete Service" button, then the 4-digit completion code
  Widget _codeCard() {
    final stage = _stage;
    final inProgress = stage == JourneyStage.inProgress;
    final needsCompleteTap = inProgress && !_completionRequested;
    final canVerify = (stage == JourneyStage.arrived) || (inProgress && _completionRequested);

    final cardTitle = inProgress ? 'Complete The Service' : 'Start With SUNNDARI CODE';
    final cardSubtitle = inProgress
        ? (_completionRequested
        ? 'Ask Your Client To Read Out The 4-digit Completion Code Shown In Their App.'
        : 'When You Have Finished, Tap "Complete Service". The Client Then Gets A 4-digit Code To Read Out.')
        : stage == JourneyStage.arrived
        ? 'Ask Your Client To Read Out The 4-digit Start Code Shown In Their App.'
        : stage == JourneyStage.onTheWay
        ? 'Tap "I Have Arrived" When You Reach The Venue. The Client Then Gets A 4-digit Start Code To Read Out.'
        : '${_onMyWayUnlockLabel != null && !_isMissed ? 'You Can Tap "On My Way" From $_onMyWayUnlockLabel (2 Hours Before). ' : ''}'
        'After You Arrive, The Client Gets A 4-digit Start Code To Read Out.';
    final buttonLabel = inProgress ? 'Verify & Complete Service' : 'Verify & Start Service';

    Widget header() => Row(
      children: [
        const SunndariIconBubble(icon: Icons.verified_user_outlined, size: 40),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(cardTitle, style: AiraText.sans(fontSize: 14, fontWeight: FontWeight.w800, color: AiraColors.roseDeep)),
              Text(cardSubtitle, style: AiraText.sans(fontSize: 11.5, color: AiraColors.charcoalSoft)),
            ],
          ),
        ),
      ],
    );

    // Before the artist has arrived there is nothing to enter yet: show only
    // the short explanation (and when "On My Way" unlocks) — no locked boxes
    // and no disabled "Verify & Start Service" button.
    if (!(stage == JourneyStage.arrived || inProgress)) {
      return AiraCard(
        padding: const EdgeInsets.all(14),
        child: header(),
      );
    }

    // In progress, code not requested yet → one button only.
    if (needsCompleteTap) {
      return AiraCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header(),
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Complete Service',
              expand: true,
              onTap: _pinBusy ? null : _requestCompletion,
            ),
          ],
        ),
      );
    }

    return AiraCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header(),
          const SizedBox(height: 16),

          // --- 4-digit code input ---
          SizedBox(
            height: 48,
            child: Stack(
              children: [
                Row(
                  children: List.generate(4, (index) {
                    final text = _otpController.text;
                    final isFocused = _otpFocusNode.hasFocus && text.length == index;
                    final char = text.length > index ? text[index] : '–';
                    return Expanded(
                      child: Container(
                        margin: EdgeInsets.only(right: index == 3 ? 0 : 6),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: canVerify ? Colors.white : AiraColors.pinkFill,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isFocused ? AiraColors.roseDeep : AiraColors.pinkBorder,
                            width: isFocused ? 1.5 : 1.0,
                          ),
                        ),
                        child: Text(
                          char,
                          style: AiraText.sans(
                            fontSize: 18,
                            fontWeight: text.length > index ? FontWeight.w700 : FontWeight.w400,
                            color: text.length > index ? AiraColors.charcoal : AiraColors.charcoalSoft,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
                // Invisible real TextField on top
                if (canVerify)
                  Positioned.fill(
                    child: TextField(
                      controller: _otpController,
                      focusNode: _otpFocusNode,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      showCursor: false,
                      cursorColor: Colors.transparent,
                      style: const TextStyle(color: Colors.transparent, fontSize: 1),
                      decoration: const InputDecoration(
                        counterText: '',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: (val) {
                        if (val.contains(RegExp(r'[^0-9]'))) {
                          _otpController.text = val.replaceAll(RegExp(r'[^0-9]'), '');
                          _otpController.selection =
                              TextSelection.fromPosition(TextPosition(offset: _otpController.text.length));
                        }
                        setState(() {});
                      },
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          PrimaryButton(
            label: buttonLabel,
            icon: canVerify ? null : Icons.lock_outline_rounded,
            expand: true,
            onTap: (canVerify && !_pinBusy) ? _verifyCode : null,
          ),
          if (!canVerify)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Available After You Arrive', style: AiraText.sans(fontSize: 11, color: AiraColors.charcoalSoft)),
              ),
            ),
          if (inProgress && _completionRequested)
            Center(
              child: TextButton(
                onPressed: _pinBusy ? null : _requestCompletion,
                child: Text("Customer Didn't Get It? Resend Code",
                    style: AiraText.sans(fontSize: 12, fontWeight: FontWeight.w600, color: AiraColors.roseDeep)),
              ),
            ),
        ],
      ),
    );
  }

  /// UI piece: booking help link.
  Widget _bookingHelpLink() => Center(
    child: TextButton.icon(
      onPressed: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => BookingHelpScreen(
          bookingId: widget.bookingId,
          serviceName: _packageLabel,
          dateTimeLabel: '$_dateText • $_timeLabel',
          onReschedule: () => _openChange(viaHelp: true),
        ),
      )),
      icon: const Icon(Icons.help_outline_rounded, size: 18, color: AiraColors.rose),
      label: Text('Booking Help', style: AiraText.sans(fontSize: 13.5, fontWeight: FontWeight.w700, color: AiraColors.roseDeep)),
    ),
  );

  /// Declines the request.
  Future<void> _decline() async {
    final reason = await showAiraCancelReasonDialog(context, clientName: _clientName, isReject: true);
    if (reason == null) return;
    await _applyStatus(_slotForCallback, SlotStatus.cancelled, reason: reason);
    if (mounted) Navigator.of(context).pop();
  }

  /// Accepts the request.
  Future<void> _accept() async {
    await _applyStatus(_slotForCallback, SlotStatus.confirmed);
    if (mounted) Navigator.of(context).pop();
  }

  /// UI: requests body.
  Widget _requestBody() {
    final b = _booking;
    final total = b?.totalAmount ?? widget.slot?.amount ?? 0;
    final fee = total * _commission / 100;
    final net = total - fee;
    final meta = PackageMeta.fromPackage(_package);
    final includes = (_package?.inclusions ?? const []).map((e) => e.inclusionText).join(', ');
    // The add-ons THIS customer actually booked (from the booking itself),
    // not every add-on the artist offers for the package.
    final bookedAddOnNames = (b?.addons ?? const <BookingAddOn>[]).map((a) => a.name).toList();
    final window = _reservedWindow;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(child: SunndariPageHeading(title: 'New Booking Request', subtitle: 'Review The Details And Accept Or Decline.')),
            _statusPill('New Request', AiraColors.blush, AiraColors.rose),
          ],
        ),
        const SizedBox(height: 14),
        _card([
          _rowItem(Icons.calendar_month_outlined, 'Booking ID', '#${widget.bookingId}',
              trailing: _statusPill('New Request', AiraColors.blush, AiraColors.rose)),
          _rowItem(Icons.person_outline_rounded, 'Client', _clientName),
          _rowItem(Icons.event_outlined, 'Date & Time', '$_dateText • $_timeLabel'),
          _rowItem(Icons.location_on_outlined, 'Venue', _locationType?.name ?? '—',
              sub: 'Exact Address Shared After Confirmation', last: (b?.notes ?? '').trim().isEmpty),
          if ((b?.notes ?? '').trim().isNotEmpty)
            _rowItem(Icons.edit_note_rounded, 'Special Request / Additional Information', b!.notes!.trim(), last: true),
        ]),
        const SizedBox(height: 12),
        _card([
          Padding(padding: const EdgeInsets.only(top: 6, bottom: 2), child: Text('Service Details', style: AiraText.serif(fontSize: 18, fontWeight: FontWeight.w700))),
          _rowItem(Icons.brush_outlined, 'Service', _packageLabel),
          _rowItem(Icons.schedule_rounded, 'Duration', _durationMinutes > 0 ? formatDuration(_durationMinutes) : '—'),
          _rowItem(Icons.format_list_bulleted_rounded, 'What’s Included', includes.isEmpty ? '—' : includes),
          _rowItem(Icons.sell_outlined, 'Brands', meta.brands.isEmpty ? '—' : meta.brands.join(' • ')),
          _rowItem(Icons.card_giftcard_outlined, 'Add-on', bookedAddOnNames.isEmpty ? 'None' : bookedAddOnNames.join(', '), last: true),
        ]),
        const SizedBox(height: 12),
        _card([
          Padding(padding: const EdgeInsets.only(top: 6, bottom: 2), child: Text('Time & Travel', style: AiraText.serif(fontSize: 18, fontWeight: FontWeight.w700))),
          _rowItem(Icons.schedule_rounded, 'Calendar Reserved', window ?? '—',
              sub: _durationMinutes > 0 ? 'Service: ${formatDuration(_durationMinutes)}' : null, last: true),
        ]),
        const SizedBox(height: 12),
        _card([
          Padding(padding: const EdgeInsets.only(top: 6, bottom: 2), child: Text('Payment Details', style: AiraText.serif(fontSize: 18, fontWeight: FontWeight.w700))),
          _rowItem(Icons.currency_rupee_rounded, 'Service Total', '₹${total.toStringAsFixed(0)}'),
          _rowItem(Icons.toll_outlined, 'Platform Deductions',
              _commission > 0 ? '−₹${fee.toStringAsFixed(0)}' : 'Shown Before Acceptance',
              sub: _commission > 0 ? '${_commission.toStringAsFixed(_commission % 1 == 0 ? 0 : 1)}% Platform Fee' : null),
          _rowItem(Icons.bar_chart_rounded, 'Your Net Earnings', _commission > 0 || total > 0 ? '₹${net.toStringAsFixed(0)}' : 'Awaiting Calculation',
              last: true),
        ]),
        if (_isMissed) ...[
          const SizedBox(height: 12),
          AiraCard(
            padding: const EdgeInsets.all(12),
            backgroundColor: const Color(0xFFFFF6DD),
            borderColor: AiraColors.warn,
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, size: 18, color: AiraColors.warn),
                const SizedBox(width: 10),
                Expanded(child: Text('This Request’s Time Has Passed, So It Can No Longer Be Accepted.',
                    style: AiraText.sans(fontSize: 12.5, color: AiraColors.charcoal, height: 1.35))),
              ],
            ),
          ),
        ] else ...[
          const SizedBox(height: 12),
          AiraCard(
            padding: const EdgeInsets.all(12),
            backgroundColor: const Color(0xFFFFF6DD),
            borderColor: AiraColors.warn,
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, size: 18, color: AiraColors.warn),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Your Net Earnings Are Confirmed Once You Accept This Booking.',
                      style: AiraText.sans(fontSize: 12.5, color: AiraColors.charcoal, height: 1.35)),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 4),
        _bookingHelpLink(),
      ],
    );
  }

  /// UI piece: manage body.
  Widget _manageBody() {
    final b = _booking;
    final active = _effectiveStatus == SlotStatus.confirmed || _effectiveStatus == SlotStatus.inProgress;
    final finished = _effectiveStatus == SlotStatus.completed || _effectiveStatus == SlotStatus.cancelled || _effectiveStatus == SlotStatus.noShow;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        const SunndariPageHeading(title: 'Manage Booking', subtitle: 'View Details And Update Your Booking Status.'),
        const SizedBox(height: 14),
        AiraCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: (_reschedulePending && _effectiveStatus == SlotStatus.confirmed && !_isMissed)
                    ? ReschedulePill(_statusRowLabel)
                    : _statusPill(
                  _statusRowLabel,
                  _effectiveStatus == SlotStatus.cancelled || _effectiveStatus == SlotStatus.noShow || _isMissed
                      ? AiraColors.errorBg
                      : const Color(0xFFE3F5EA),
                  _effectiveStatus == SlotStatus.cancelled || _effectiveStatus == SlotStatus.noShow || _isMissed
                      ? AiraColors.errorText
                      : AiraColors.success,
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: const BoxDecoration(color: AiraColors.blush, shape: BoxShape.circle),
                    child: const Icon(Icons.person_outline_rounded, color: AiraColors.roseDeep, size: 26),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Client', style: AiraText.sans(fontSize: 11.5, color: AiraColors.charcoalSoft)),
                        Text(_clientName, style: AiraText.sans(fontSize: 18, fontWeight: FontWeight.w800, color: AiraColors.roseDeep)),
                        Text(_packageLabel, style: AiraText.sans(fontSize: 13, color: AiraColors.charcoalSoft)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _rowItem(Icons.event_outlined, 'Date & Time', '$_dateText • $_timeLabel'),
              _rowItem(Icons.location_on_outlined, 'Client Venue', _locationLabel ?? '—',
                  last: (b?.notes ?? '').trim().isEmpty),
              if ((b?.notes ?? '').trim().isNotEmpty)
                _rowItem(Icons.edit_note_rounded, 'Special Request / Additional Information', b!.notes!.trim(), last: true),
              const SizedBox(height: 10),
              Row(
                children: [
                  // Chat only exists for pending/confirmed/in-progress bookings, so hide the button otherwise.
                  if (_effectiveStatus != SlotStatus.completed &&
                      _effectiveStatus != SlotStatus.cancelled &&
                      _effectiveStatus != SlotStatus.noShow) ...[
                    Expanded(
                      child: GhostButton(
                        label: 'Contact Client',
                        icon: Icons.chat_bubble_outline,
                        small: true,
                        expand: true,
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => ChatScreen(bookingId: widget.bookingId, title: _clientName),
                        )),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: PrimaryButton(label: 'Get Directions', icon: Icons.near_me_outlined, small: true, expand: true, onTap: _getDirections),
                  ),
                ],
              ),
            ],
          ),
        ),
        _rescheduleCard(),
        if ((active && !_isMissed) || _effectiveStatus == SlotStatus.completed) ...[
          const SizedBox(height: 12),
          AiraCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Booking Progress', style: AiraText.serif(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                _progress(),
                const SizedBox(height: 14),
                JourneyActionButton(
                  slot: _slotForCallback,
                  statuses: _statuses,
                  onUpdateStatus: _applyStatus,
                  onRefresh: _onJourneyRefresh,
                  // Same booking as the progress card above → they always agree.
                  booking: _booking,
                  small: false,
                ),
              ],
            ),
          ),
        ],
        if (active && !_isMissed) ...[
          const SizedBox(height: 12),
          _codeCard(),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: GhostButton(
                  label: 'Reschedule',
                  icon: Icons.event_repeat_outlined,
                  small: true,
                  expand: true,
                  onTap: () => _openChange(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GhostButton(
                  label: 'Cancel Booking',
                  icon: Icons.close_rounded,
                  small: true,
                  expand: true,
                  color: AiraColors.errorText,
                  onTap: () async {
                    final reason = await showAiraCancelReasonDialog(context, clientName: _clientName);
                    if (reason == null) return;
                    await _applyStatus(_slotForCallback, SlotStatus.cancelled, reason: reason);
                    if (mounted) Navigator.of(context).pop();
                  },
                ),
              ),
            ],
          ),
        ],
        if (_isMissed && !finished) ...[
          const SizedBox(height: 12),
          AiraCard(
            padding: const EdgeInsets.all(12),
            backgroundColor: AiraColors.errorBg,
            child: Text('This Appointment’s Time Has Passed Without Starting. You Can Cancel It.',
                style: AiraText.sans(fontSize: 12.5, color: AiraColors.errorText, height: 1.35)),
          ),
          const SizedBox(height: 10),
          GhostButton(
            label: 'Cancel Booking',
            icon: Icons.close_rounded,
            expand: true,
            color: AiraColors.errorText,
            onTap: () async {
              final reason = await showAiraCancelReasonDialog(context, clientName: _clientName);
              if (reason == null) return;
              await _applyStatus(_slotForCallback, SlotStatus.cancelled, reason: reason);
              if (mounted) Navigator.of(context).pop();
            },
          ),
        ],
        if (finished) ...[
          const SizedBox(height: 12),
          _card([
            _rowItem(Icons.currency_rupee_rounded, 'Service Total', '₹${(b?.totalAmount ?? widget.slot?.amount ?? 0).toStringAsFixed(0)}',
                last: false),
            for (final a in b?.addons ?? const <BookingAddOn>[])
              _rowItem(Icons.add_circle_outline_rounded, 'Add-on · ${a.name}', '₹${a.price.toStringAsFixed(0)}', last: false),
            if ((b?.travelFee ?? 0) > 0)
              _rowItem(Icons.directions_car_outlined, 'Travel Fee', '₹${b!.travelFee.toStringAsFixed(0)}', last: false),
            if (b?.platformFee != null)
              _rowItem(Icons.percent_rounded, 'Platform Fee', '− ₹${b!.platformFee!.toStringAsFixed(0)}', last: false),
            if (b?.netAmount != null)
              _rowItem(Icons.payments_outlined, 'You Receive', '₹${b!.netAmount!.toStringAsFixed(0)}',
                  last: _paymentStatusLabel == null && b.cancellationReason == null),
            if (_paymentStatusLabel != null)
              _rowItem(Icons.account_balance_wallet_outlined, 'Payment', _paymentStatusLabel!, last: b?.cancellationReason == null),
            if (b?.cancellationReason != null) _rowItem(Icons.info_outline_rounded, 'Cancellation Reason', b!.cancellationReason!, last: true),
          ]),
        ],
        const SizedBox(height: 8),
        _bookingHelpLink(),
      ],
    );
  }

  /// Builds the UI.
  @override
  Widget build(BuildContext context) {
    final request = _isRequest && !_loading && _error == null;
    final canAct = request && !_isMissed;

    return Scaffold(
      backgroundColor: AiraColors.bg,
      body: SunndariBackground(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SunndariAppBar(onBack: () => Navigator.of(context).pop()),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4, color: AiraColors.rose))
                    : _error != null
                    ? AiraErrorState(message: _error!, onRetry: _load)
                    : (_isRequest ? _requestBody() : _manageBody()),
              ),
              if (canAct)
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, -3))],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GhostButton(
                          label: 'Decline',
                          icon: Icons.close_rounded,
                          expand: true,
                          color: AiraColors.errorText,
                          onTap: _decline,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: PrimaryButton(label: 'Accept Booking', icon: Icons.check_rounded, expand: true, onTap: _accept),
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