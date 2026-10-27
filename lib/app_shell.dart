// FILE: app_shell.dart  |  MAIN APP SHELL (after login)
// Hosts the bottom-nav tabs: Home, Bookings/Business, Calendar, Earnings, Profile (+ Grow / Learn).
// Loads bookings + statuses once, listens to live Firestore booking updates, and enforces the profile gate.

import 'dart:async';
import 'package:aira_app/screens/booking_detail_screen.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'models/models.dart';
import 'theme/tokens.dart';
import 'widgets/common.dart';
import 'screens/home_screen.dart';
import 'screens/business_screen.dart';
import 'screens/calendar_screen.dart';
import 'screens/grow_screen.dart';
import 'screens/learning_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/auth/login_screen.dart';
import 'utils/service_locator.dart';
import 'utils/app_session.dart';
import 'utils/app_feedback.dart';
import 'utils/notification_badge.dart';
import 'services/push_notification_service.dart';
import 'services/service_announcement_service.dart';
import 'api/help_center_notifier.dart';
import 'utils/autostart_helper.dart';
import 'models/artist/artist_profile.dart';
import 'models/booking/booking.dart';
import 'models/core/status_item.dart';
import 'models/artist/create_portfolio.dart';
import 'models/enums/media_type_enum.dart';
import 'helper/booking_stats.dart';
import 'utils/profile_completeness.dart';
import 'utils/share_profile.dart';
import 'screens/auth/registration_status_screen.dart';
import 'screens/onboarding/artist_page_setup_screen.dart';

/// Main app container with bottom navigation (after login).
class AiraAppShell extends StatefulWidget {
  const AiraAppShell({super.key});

  @override
  State<AiraAppShell> createState() => _AiraAppShellState();
}

/// Holds current tab, bookings, statuses and live Firestore listeners.
class _AiraAppShellState extends State<AiraAppShell> with WidgetsBindingObserver {
  String _screen = 'home';
  String _businessTab = 'insights';
  String _growTab = 'marketing';
  String? _toast;
  Timer? _toastTimer;

  bool _loading = true;
  ArtistProfile? _profile;
  List<Booking> _bookings = [];
  List<StatusItem> _bookingStatuses = [];
  bool _hasClash = false;
  bool _profileIncomplete = false;
  bool _gateChecked = false;
  String? _profileHint;
  StreamSubscription<List<Booking>>? _bookingsSub;
  final Map<int, String> _customerNames = {};
  final Map<int, String> _packageNames = {}; // packageId → package name (for the booking cards)

  /// Runs once when the screen opens; starts: _enforceProfileGate(), _loadData().
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _enforceProfileGate();
    _loadData();
    // Auto-refresh: every 45 s while the app is open, and whenever a push arrives.
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (_appInForeground) {
        _loadData(silent: true);
        // A "new service" popup that had to wait (another screen was open) is retried here.
        if (ServiceAnnouncementService.instance.hasDeferred) _checkServiceAnnouncements();
      }
    });
    NotificationBadge.instance.newNotificationTick.addListener(_onPushArrived);
    PushNotificationService.instance.initMessaging();
    HelpCenterNotifier.instance.start(ServiceLocator.apiService);
    NotificationBadge.instance.refresh();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AutostartHelper.promptIfNeeded(context);
    });
  }

  Timer? _autoRefreshTimer;
  bool _appInForeground = true;
  bool _refreshing = false;
  DateTime _lastLoad = DateTime.fromMillisecondsSinceEpoch(0);
  int? _liveArtistId;

  /// App went to background / came back.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appInForeground = state == AppLifecycleState.resumed;
    if (_appInForeground) {
      _loadData(silent: true); // coming back to the app → fetch the latest
      NotificationBadge.instance.refresh();
      _checkServiceAnnouncements();
    }
  }

  /// A push notification arrived while the app is open → refresh bookings (and look for a new-service popup).
  void _onPushArrived() {
    _loadData(silent: true);
    _checkServiceAnnouncements();
  }

  /// Admin announced a new service → popup on the home screen (see services/service_announcement_service.dart).
  /// Runs only after the profile gate passed (so an unapproved / incomplete artist never gets it).
  void _checkServiceAnnouncements({bool force = false}) {
    if (!mounted || !_gateChecked) return;
    ServiceAnnouncementService.instance.checkAndShow(context, force: force);
  }

  /// Enforces profile gate.
  Future<void> _enforceProfileGate() async {
    ArtistProfile? profile;
    try {
      profile = await ServiceLocator.artistService.getProfile();
    } catch (_) {}
    final complete = await ArtistPageSetup.isProfileComplete(profile: profile);
    if (!mounted) return;
    if (complete) {
      if (await ArtistPageReview.pending()) {
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const ArtistPageUnderReviewScreen()),
              (r) => false,
        );
        return;
      }
      setState(() => _gateChecked = true);
      // First look for a "new service" announcement as soon as the home screen is ready.
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkServiceAnnouncements(force: true));
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => RegistrationStatusScreen(approvalStatusId: profile?.approvalStatusId)),
          (r) => false,
    );
  }

  /// Frees controllers / listeners when the screen closes.
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoRefreshTimer?.cancel();
    NotificationBadge.instance.newNotificationTick.removeListener(_onPushArrived);
    _toastTimer?.cancel();
    _reloadTimer?.cancel();
    _bookingsSub?.cancel();
    super.dispose();
  }

  /// Listens to for live bookings.
  void _listenForLiveBookings(int artistId) {
    _bookingsSub?.cancel();
    _bookingsSub = ServiceLocator.firestoreBookingService
        .artistBookingsStream(artistId)
        .listen(
          (liveBookings) {
        if (!mounted || liveBookings.isEmpty) return;
        final merged = {for (final b in _bookings) b.bookingId: b};
        for (final b in liveBookings) {
          if (_paymentBlockedIds.contains(b.bookingId)) continue;
          final existing = merged[b.bookingId];
          if (existing == null) {
            // Booking the server list (paid only) does not contain: it may be UNPAID, or newly paid.
            // Never show it from Firestore; ask the server once (no reload loops).
            if (_unconfirmedLiveIds.add(b.bookingId)) _scheduleRestReload();
            continue;
          }
          if (_isNewerOrEqual(b, existing)) {
            merged[b.bookingId] = _mergeLiveFields(existing, b);
          }
        }
        final bookings = merged.values.toList()
          ..sort((a, b) => b.bookingDate.compareTo(a.bookingDate));
        if (kDebugMode) {
          final todayCount = BookingStats(bookings, _bookingStatuses).todaysAppointments.length;
          debugPrint('[Dashboard] Firestore live merge: incoming=${liveBookings.length}, '
              'merged_total=${bookings.length}, today=$todayCount');
        }
        setState(() {
          _bookings = bookings;
          _hasClash = _detectClash(bookings, _bookingStatuses);
        });
        _loadCustomerNames(bookings);
        _loadPackageNames(bookings);
      },
      onError: (e) {
        if (kDebugMode) debugPrint('[AppShell] live bookings listener error: $e');
      },
    );
  }

  /// Returns true if newer or equal.
  bool _isNewerOrEqual(Booking candidate, Booking current) {
    final a = DateTime.tryParse(candidate.updatedAt ?? '');
    final b = DateTime.tryParse(current.updatedAt ?? '');
    if (a == null || b == null) return true;
    return !a.isBefore(b);
  }

  Timer? _reloadTimer;
  /// Bookings the server refused to confirm because payment is incomplete (hidden until the app restarts).
  final Set<int> _paymentBlockedIds = {};
  final Set<int> _unconfirmedLiveIds = {}; // live bookings not in the paid list — checked with the server once

  /// Re-fetches bookings from REST (debounced) — used when Firestore shows a booking we don't know yet.
  void _scheduleRestReload() {
    _reloadTimer?.cancel();
    _reloadTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) _loadData();
    });
  }

  /// Merges live fields (status etc. from Firestore, everything else kept from REST).
  Booking _mergeLiveFields(Booking rest, Booking live) {
    String? pick(String? a, String? b) => (a != null && a.isNotEmpty) ? a : b;
    return Booking(
      bookingId: rest.bookingId,
      customerId: rest.customerId,
      artistId: rest.artistId,
      subCategoryId: rest.subCategoryId,
      packageId: rest.packageId,
      locationTypeId: rest.locationTypeId,
      addressId: rest.addressId,
      bookingDate: rest.bookingDate,
      startTime: rest.startTime,
      endTime: rest.endTime,
      statusId: live.statusId,
      paymentStatusId: live.paymentStatusId ?? rest.paymentStatusId,
      totalAmount: rest.totalAmount,
      notes: rest.notes,
      cancelledBy: live.cancelledBy ?? rest.cancelledBy,
      cancellationReason: live.cancellationReason ?? rest.cancellationReason,
      expiresAt: rest.expiresAt,
      createdAt: rest.createdAt,
      updatedAt: live.updatedAt ?? rest.updatedAt,
      onMyWayAt: pick(live.onMyWayAt, rest.onMyWayAt),
      arrivedAt: pick(live.arrivedAt, rest.arrivedAt),
      serviceStartedAt: pick(live.serviceStartedAt, rest.serviceStartedAt),
      serviceCompletedAt: pick(live.serviceCompletedAt, rest.serviceCompletedAt),
      platformFee: rest.platformFee,
      netAmount: rest.netAmount,
      travelFee: rest.travelFee,
      travelTimeMinutes: rest.travelTimeMinutes,
      returnBufferMinutes: rest.returnBufferMinutes,
      addons: rest.addons,
    );
  }

  /// Loads data.
  /// [silent] = background refresh: no spinner, no error toast.
  Future<void> _loadData({bool silent = false}) async {
    if (_refreshing && silent) return; // one background refresh at a time
    _refreshing = true;
    if (!silent) setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ServiceLocator.artistService.getProfile(),
        ServiceLocator.bookingService.getAllBookings(limit: 200),
      ]);
      final profile = results[0] as ArtistProfile;
      // The server returns PAID bookings only (filter_key=paymentStatus&filter_value=paid).
      final bookings = (results[1] as List<Booking>).where((b) => !_paymentBlockedIds.contains(b.bookingId)).toList();
      _unconfirmedLiveIds.removeWhere((id) => bookings.any((b) => b.bookingId == id));

      List<StatusItem> statuses = [];
      try {
        statuses = await ServiceLocator.coreService.getBookingStatuses();
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[Dashboard] booking-statuses lookup failed — status '
              'badges will show as "Open" until this is retried: $e');
        }
      }

      if (!mounted) return;
      setState(() {
        _profile = profile;
        _bookings = bookings;
        _bookingStatuses = statuses;
        _hasClash = _detectClash(bookings, statuses);
        _loading = false;
      });
      if (kDebugMode) {
        final todayCount = BookingStats(bookings, statuses).todaysAppointments.length;
        debugPrint('[Dashboard] REST load done: ${bookings.length} bookings, today=$todayCount');
      }
      _loadCustomerNames(bookings);
      _loadPackageNames(bookings);
      _checkProfileCompleteness(profile);
      if (_liveArtistId != profile.artistId) {
        _liveArtistId = profile.artistId;
        _listenForLiveBookings(profile.artistId);
      }
      _lastLoad = DateTime.now();
    } catch (e) {
      if (!mounted) return;
      if (!silent) {
        setState(() => _loading = false);
        _showErrorToast(e, onRetry: _loadData);
      }
    } finally {
      _refreshing = false;
    }
  }

  /// Loads the package (service) name of every booking
  Future<void> _loadPackageNames(List<Booking> bookings) async {
    final ids = bookings.map((b) => b.packageId).toSet()
      ..removeWhere((id) => id == 0 || _packageNames.containsKey(id));
    if (ids.isEmpty) return;
    await Future.wait(ids.map((id) async {
      try {
        final pkg = await ServiceLocator.artistService.getPackage(id);
        if (!mounted) return;
        if (pkg.name.trim().isNotEmpty) setState(() => _packageNames[id] = pkg.name.trim());
      } catch (_) {}
    }));
  }

  /// Loads customer names.
  Future<void> _loadCustomerNames(List<Booking> bookings) async {
    final ids = bookings.map((b) => b.customerId).toSet()
      ..removeWhere((id) => id == 0 || _customerNames.containsKey(id));
    if (ids.isEmpty) return;

    await Future.wait(ids.map((id) async {
      try {
        final profile = await ServiceLocator.userService.getProfile(id);
        if (!mounted) return;
        if (profile.name.trim().isNotEmpty) {
          setState(() => _customerNames[id] = profile.name.trim());
        }
      } catch (_) {
      }
    }));
  }

  /// Checks profile completeness.
  Future<void> _checkProfileCompleteness([ArtistProfile? profile]) async {
    try {
      final c = await ProfileCompleteness.load(profile: profile ?? _profile);
      if (!mounted) return;
      setState(() {
        _profileIncomplete = !c.isComplete;
        _profileHint = c.nextHint;
      });
    } catch (_) {
    }
  }

  /// Detects clash.
  bool _detectClash(List<Booking> bookings, List<StatusItem> statuses) {
    final active = bookings.where((b) {
      final label = _statusLabel(b.statusId, statuses);
      return label != 'cancelled' && label != 'no_show' && label != 'completed';
    }).toList();
    for (var i = 0; i < active.length; i++) {
      for (var j = i + 1; j < active.length; j++) {
        if (active[i].bookingDate == active[j].bookingDate &&
            active[i].startTime == active[j].startTime) {
          return true;
        }
      }
    }
    return false;
  }

  /// Status label.
  String _statusLabel(int statusId, List<StatusItem> statuses) {
    final m = statuses.where((s) => s.statusId == statusId);
    return m.isNotEmpty ? m.first.name.toLowerCase() : '';
  }

  /// Maps status.
  SlotStatus _mapStatus(int statusId, {String? cancelledBy}) =>
      BookingStats.mapStatus(statusId, _bookingStatuses, cancelledBy: cancelledBy);

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

  List<BookingSlot> get _slots {
    final list = [..._bookings]..sort((a, b) {
      final d = a.bookingDate.compareTo(b.bookingDate);
      return d != 0 ? d : a.startTime.compareTo(b.startTime);
    });
    return list
        .map((b) => BookingSlot(
      bookingId: b.bookingId,
      date: b.bookingDate,
      time: _formatTime(b.startTime),
      rawStartTime: b.startTime,
      client: _customerNames[b.customerId] ?? 'Customer',
      service: _packageNames[b.packageId] ?? 'Service',
      status: _mapStatus(b.statusId, cancelledBy: b.cancelledBy),
      amount: b.totalAmount,
    ))
        .toList();
  }

  /// Shows toast.
  void _showToast(String text) {
    _toastTimer?.cancel();
    setState(() => _toast = text);
    _toastTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  /// Shows error toast.
  void _showErrorToast(Object error, {VoidCallback? onRetry}) {
    if (!mounted) return;
    AppFeedback.showError(context, error, onRetry: onRetry);
  }

  /// Navigates to.
  /// Navigates to.
  void _navigate(String target, [String? tab]) {
    // नया कोड: अगर बुकिंग डिटेल पर क्लिक हुआ है, तो अगली स्क्रीन पर भेजें
    if (target == 'booking_detail' && tab != null) {
      final bId = int.tryParse(tab);
      if (bId != null) {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => BookingDetailScreen(
            bookingId: bId,
            statuses: _bookingStatuses,
            onRefresh: _loadData,
          ),
        ));
        return;
      }
    }

    setState(() {
      if (target == 'bookings') {
        _screen = 'business';
        _businessTab = 'booking';
      } else if (target == 'earnings') {
        _screen = 'business';
        _businessTab = 'finance';
      } else {
        _screen = target;
        if (target == 'business' && tab != null) _businessTab = tab;
        if (target == 'grow' && tab != null) _growTab = tab;
      }
    });

    if (target == 'home') _checkProfileCompleteness();
    // Opening a tab → refresh if the data is older than 10 s
    if (DateTime.now().difference(_lastLoad).inSeconds > 10) _loadData(silent: true);
  }

  /// Updates booking status.
  Future<void> _updateBookingStatus(BookingSlot slot, SlotStatus next, {String? reason}) async {
    if (slot.bookingId == null) return;
    final apiStatus = switch (next) {
      SlotStatus.confirmed => BookingStatusEnum.confirmed,
      SlotStatus.inProgress => BookingStatusEnum.inProgress,
      SlotStatus.completed => BookingStatusEnum.completed,
      SlotStatus.cancelled => BookingStatusEnum.cancelled,
      SlotStatus.noShow => BookingStatusEnum.noShow,
      _ => BookingStatusEnum.confirmed,
    };
    _showToast('Updating Booking…');
    try {
      await ServiceLocator.bookingService.updateBookingStatus(slot.bookingId!, apiStatus, reason: reason);
      await _loadData();
      _showToast('Booking Updated ✓');
    } catch (e) {
      final text = e.toString().toLowerCase();
      if (text.contains('payment') && (text.contains('complete') || text.contains('pending'))) {
        // The server says payment is incomplete → hide this booking (it must not be shown yet).
        _paymentBlockedIds.add(slot.bookingId!);
        if (mounted) {
          setState(() => _bookings = _bookings.where((b) => b.bookingId != slot.bookingId).toList());
        }
        _showToast('This Booking Is Waiting For The Customer\'s Payment');
        return;
      }
      _showErrorToast(e, onRetry: () => _updateBookingStatus(slot, next, reason: reason));
    }
  }

  /// Logs the user out.
  Future<void> _logout() async {

    await PushNotificationService.instance.resetForLogout();
    HelpCenterNotifier.instance.stop();
    try {
      await ServiceLocator.authService.logout();
    } catch (_) {
    }
    NotificationBadge.instance.clear();
    if (!mounted) return;
    Navigator.of(context)
        .pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (r) => false);
  }

  /// Posts portfolio.
  Future<void> _postPortfolio() async {
    try {
      final picker = ImagePicker();
      final xfile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (xfile == null) return;

      int subCategoryId = 1;
      try {
        final services = await ServiceLocator.artistService.getAllServices();
        final list = services is Map ? services['data'] : services;
        if (list is List && list.isNotEmpty) {
          final first = list.first;
          if (first is Map && first['subCategoryId'] != null) {
            subCategoryId = first['subCategoryId'] as int;
          }
        }
      } catch (_) {
      }

      _showToast('Uploading To Your Portfolio…');
      await ServiceLocator.artistService.createPortfolio(CreatePortfolio(
        mediaType: MediaTypeEnum.image,
        subCategoryId: subCategoryId,
        file: xfile,
        caption: 'Shared Via Sunndari',
      ));
      _showToast('Added To Your Portfolio ✓');
    } catch (e) {
      _showErrorToast(e);
    }
  }

  /// Date label.
  String get _dateLabel {
    final now = DateTime.now();
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${days[now.weekday - 1]}, ${now.day} ${months[now.month - 1]}';
  }

  /// Active nav key.
  String get _activeNavKey {
    if (_screen == 'business') return _businessTab == 'finance' ? 'earnings' : 'bookings';
    if (_screen == 'calendar' || _screen == 'profile' || _screen == 'home') return _screen;
    return '';
  }

  /// Builds the UI.
  @override
  Widget build(BuildContext context) {
    if (!_gateChecked) {
      return const Scaffold(
        backgroundColor: AiraColors.bg,
        body: Center(child: CircularProgressIndicator(strokeWidth: 2.4, color: AiraColors.rose)),
      );
    }
    final stats = BookingStats(_bookings, _bookingStatuses);
    final todays = stats.todaysAppointments;
    final pendingConfirmationsCount =
        _bookings.where((b) => _mapStatus(b.statusId, cancelledBy: b.cancelledBy) == SlotStatus.pending).length;

    late final Widget mainScreen;
    switch (_screen) {
      case 'business':
        mainScreen = BusinessScreen(
          activeTab: _businessTab,
          onTabSelect: (t) => setState(() => _businessTab = t),
          onNavigate: _navigate,
          slots: _slots,
          loading: _loading,
          onUpdateStatus: _updateBookingStatus,
          bookings: _bookings,
          bookingStatuses: _bookingStatuses,
          customerNames: _customerNames,
          onWithdraw: () => AppFeedback.showInfo(context, "Payouts Aren't Available In This Preview Yet"),
          onRefresh: _loadData,
        );
        break;
      case 'calendar':
        mainScreen = CalendarScreen(
          slots: _slots,
          statuses: _bookingStatuses,
          onUpdateStatus: _updateBookingStatus,
          onRefresh: _loadData,
        );
        break;
      case 'grow':
        mainScreen = GrowScreen(
          activeTab: _growTab,
          onTabSelect: (t) => setState(() => _growTab = t),
          onPost: _postPortfolio,
          onShare: () => shareArtistProfile(context),
        );
        break;
      case 'learn':
        mainScreen = const LearningScreen();
        break;
      case 'profile':
        mainScreen = SettingsScreen(
          name: AppSession.instance.name ?? '',
          city: _profile?.city,
          profile: _profile,
          onLogout: _logout,
          onProfileUpdated: _loadData,
        );
        break;
      case 'home':
      default:
        if (kDebugMode) {
          debugPrint('[Dashboard] HomeScreen build: loading=$_loading, '
              'bookingsToday=${todays.length}, bookingsTotal=${_bookings.length}');
        }

        // --- MAP TODAY'S BOOKINGS TO BookingSlot FOR HOME SCREEN ---
        final todaysSlots = todays.map((b) => BookingSlot(
          bookingId: b.bookingId,
          date: b.bookingDate,
          time: _formatTime(b.startTime),
          rawStartTime: b.startTime,
          client: _customerNames[b.customerId] ?? 'Customer',
          service: _packageNames[b.packageId] ?? 'Service',
          status: _mapStatus(b.statusId, cancelledBy: b.cancelledBy),
          amount: b.totalAmount,
        )).toList()
          ..sort((a, b) => a.rawStartTime?.compareTo(b.rawStartTime ?? '') ?? 0); // Sort by time

        mainScreen = HomeScreen(
          onNavigate: _navigate,
          artistName: AppSession.instance.name ?? '',
          dateLabel: _dateLabel,
          loading: _loading,
          bookingsThisMonth: stats.thisMonthAppointments.length,
          expectedEarningsToday: todays.fold<double>(0, (s, b) => s + b.totalAmount),
          pendingConfirmations: pendingConfirmationsCount,
          avgRating: _profile?.avgRating ?? 0,
          showCompleteProfileBanner: !_loading && _profileIncomplete,
          profileHint: _profileHint,
          todaysBookings: todaysSlots, // PASSING THE DATA HERE
          acceptingBookings: _profile?.isAcceptingBookings ?? true,
          onCompleteProfile: () => _navigate('profile'),
          briefingText: todays.isEmpty
              ? "You're All Clear — No Bookings On The Calendar Today."
              : 'You Have ${todays.length} Booking${todays.length == 1 ? '' : 's'} And '
              '₹${todays.fold<double>(0, (s, b) => s + b.totalAmount).toStringAsFixed(0)} Expected Today.'
              '${_hasClash ? ' Two bookings clash — check your calendar.' : ''}',
        );
    }

    return Scaffold(
      backgroundColor: AiraColors.bg,
      extendBody: false,
      body: SafeArea(
        child: ClipRect(
          child: Stack(
            children: [
              Positioned.fill(
                child: (_screen == 'home' || _screen == 'business' || _screen == 'calendar')
                    ? RefreshIndicator(
                        color: AiraColors.rose,
                        onRefresh: () => _loadData(silent: true),
                        child: mainScreen,
                      )
                    : mainScreen,
              ),
              if (_toast != null) AiraToast(text: _toast!),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: AiraBottomNav(active: _activeNavKey, onSelect: _navigate),
      ),
    );
  }
}