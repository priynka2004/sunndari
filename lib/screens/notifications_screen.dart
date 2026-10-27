// FILE: screens/notifications_screen.dart
// SCREEN: Notifications list (API + Firestore), mark read / mark all read.

import 'dart:async';

import 'package:flutter/material.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../models/notification/app_notification.dart';
import '../utils/app_feedback.dart';
import '../utils/app_session.dart';
import '../utils/service_locator.dart';
import '../utils/notification_badge.dart';
import 'notification_detail_screen.dart';
import 'packages_screen.dart' show AddServiceFromNotificationScreen;

/// SCREEN: Notifications list (API + Firestore), mark read / mark all read.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

/// State of [NotificationsScreen] — holds the screen data and logic.
class _NotificationsScreenState extends State<NotificationsScreen> {
  String _tab = 'all';
  bool _loading = true;
  String? _error;
  List<AppNotification> _restItems = [];
  List<AppNotification> _liveItems = [];
  StreamSubscription<List<AppNotification>>? _liveSub;

  /// Runs once when the screen opens; starts: _load(), _listenLive().
  @override
  void initState() {
    super.initState();
    _load();
    _listenLive();
    NotificationBadge.instance.newNotificationTick.addListener(_onPushArrived);
  }

  /// Frees controllers / listeners when the screen closes.
  @override
  void dispose() {
    NotificationBadge.instance.newNotificationTick.removeListener(_onPushArrived);
    _liveSub?.cancel();
    super.dispose();
  }

  /// Listens to live.
  /// API: firestoreNotificationService.notificationsStream
  void _listenLive() {
    final userId = AppSession.instance.userId;
    if (userId == null) return;
    // API call: firestoreNotificationService.notificationsStream
    _liveSub = ServiceLocator.firestoreNotificationService.notificationsStream(userId).listen(
          (items) {
        if (!mounted) return;
        setState(() => _liveItems = items);
        NotificationBadge.instance.clear();
      },
      onError: (e) {
      },
    );
  }

  /// Returns true if booking notification.
  bool _isBookingNotification(AppNotification n) => true;

  List<AppNotification> get _merged {
    final byKey = <String, AppNotification>{};
    for (final n in _restItems) {
      if (!_isBookingNotification(n)) continue;
      byKey[n.notificationId > 0 ? 'id:${n.notificationId}' : 'rest:${n.hashCode}'] = n;
    }
    for (final n in _liveItems) {
      if (!_isBookingNotification(n)) continue;
      byKey[n.notificationId > 0 ? 'id:${n.notificationId}' : 'doc:${n.firestoreDocId}'] = n;
    }
    final list = byKey.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  /// Callback when push arrived happens.
  void _onPushArrived() {
    if (!mounted) return;
    _refreshQuiet();
  }

  /// Refreshes quiet.
  /// API: localNotificationBuilder.build
  Future<void> _refreshQuiet() async {
    try {
      // API call: localNotificationBuilder.build
      final list = await ServiceLocator.localNotificationBuilder.build();
      if (!mounted) return;
      setState(() => _restItems = list);
      NotificationBadge.instance.clear();
    } catch (_) {
    }
  }

  /// Loads this screen's data.
  /// API: localNotificationBuilder.build
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // API call: localNotificationBuilder.build
      final list = await ServiceLocator.localNotificationBuilder.build();
      if (!mounted) return;
      setState(() {
        _restItems = list;
        _loading = false;
      });
      NotificationBadge.instance.clear();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_liveItems.isEmpty) {
          _error = e.toString().replaceFirst('Exception: ', '');
        }
      });
    }
  }

  /// Marks read.
  /// Uses 2 APIs (see inline notes).
  Future<void> _markRead(AppNotification n) async {
    if (n.isRead) return;
    if (n.firestoreDocId != null) {
      final userId = AppSession.instance.userId;
      setState(() {
        _liveItems = _liveItems
            .map((x) => x.firestoreDocId == n.firestoreDocId ? x.copyWith(isRead: true) : x)
            .toList();
      });
      if (userId != null) {
        try {
          // API call: firestoreNotificationService.markAsRead
          await ServiceLocator.firestoreNotificationService.markAsRead(userId, n.firestoreDocId!);
        } catch (_) {
        }
      }
      return;
    }
    setState(() {
      _restItems =
          _restItems.map((x) => x.notificationId == n.notificationId ? x.copyWith(isRead: true) : x).toList();
    });
    try {
      // API call: localNotificationBuilder.markRead
      await ServiceLocator.localNotificationBuilder.markRead(n.notificationId);
    } catch (_) {
    }
  }

  /// Opens detail.
  Future<void> _openDetail(AppNotification n) async {
    _markRead(n);
    // Admin's "add this special service" notification → straight to the Add Service screen.
    if (n.isAddServicePrompt) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => AddServiceFromNotificationScreen(subCategoryId: n.subCategoryId)),
      );
      return;
    }
    // Navigates to NotificationDetailScreen
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => NotificationDetailScreen(notificationId: n.notificationId, notification: n)),
    );
  }

  /// Marks all read.
  /// Uses 2 APIs (see inline notes).
  Future<void> _markAllRead() async {
    setState(() {
      _restItems = _restItems.map((x) => x.copyWith(isRead: true)).toList();
      _liveItems = _liveItems.map((x) => x.copyWith(isRead: true)).toList();
    });
    final userId = AppSession.instance.userId;
    try {
      await Future.wait([
        // API call: localNotificationBuilder.markAllRead
        ServiceLocator.localNotificationBuilder.markAllRead(_restItems),
        // API call: firestoreNotificationService.markAllAsRead
        if (userId != null) ServiceLocator.firestoreNotificationService.markAllAsRead(userId),
      ]);
    } catch (e) {
      if (mounted) {
        AppFeedback.showError(context, e);
      }
    }
  }

  /// Time ago.
  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just Now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m Ago';
    if (diff.inHours < 24) return '${diff.inHours}h Ago';
    return '${diff.inDays}d Ago';
  }

  /// Returns true if booking type.
  bool _isBookingType(AppNotification n) => n.bookingId != null || n.type.toLowerCase().contains('booking');

  /// Icon for.
  IconData _iconFor(AppNotification n) {
    final t = n.type.toLowerCase();
    if (n.isAddServicePrompt) return Icons.auto_awesome_outlined; // "New service: …" announcement
    if (t.contains('chat')) return Icons.chat_bubble_outline_rounded;
    if (t.contains('otp')) return Icons.pin_outlined;
    if (t.contains('reschedule')) return Icons.event_repeat_outlined;
    if (t.contains('cancel')) return Icons.event_busy_outlined;
    if (t.contains('booking')) return Icons.event_note_outlined;
    if (t.contains('help')) return Icons.support_agent_outlined;
    if (t.contains('approv') || t.contains('live')) return Icons.campaign_outlined;
    return Icons.notifications_none_rounded;
  }

  /// Builds the UI.
  @override
  Widget build(BuildContext context) {
    final all = _merged;
    final unread = all.where((n) => !n.isRead).length;
    final items = switch (_tab) {
      'bookings' => all.where(_isBookingType).toList(),
      'account' => all.where((n) => !_isBookingType(n)).toList(),
      _ => all,
    };

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
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: SunndariPageHeading(title: 'Notifications'),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Row(
                  children: [
                    for (final t in const [('all', 'All'), ('bookings', 'Bookings'), ('account', 'Account')]) ...[
                      Expanded(
                        child: AiraPill(
                          label: t.$2,
                          active: _tab == t.$1,
                          onTap: () => setState(() => _tab = t.$1),
                        ),
                      ),
                      if (t.$1 != 'account') const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Row(
                  children: [
                    Expanded(child: Text('Recent', style: AiraText.serif(fontSize: 18))),
                    if (unread > 0)
                      GestureDetector(
                        onTap: _markAllRead,
                        child: Text('Mark All As Read',
                            style: AiraText.sans(fontSize: 12.5, fontWeight: FontWeight.w700, color: AiraColors.rose)),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4, color: AiraColors.rose))
                    : (_error != null && all.isEmpty)
                        ? AiraErrorState(message: _error!, onRetry: _load)
                        : items.isEmpty
                            ? Center(
                                child: Text("You're All Caught Up ✨",
                                    style: AiraText.sans(fontSize: 13.5, color: AiraColors.charcoalSoft)),
                              )
                            : RefreshIndicator(
                                onRefresh: _load,
                                color: AiraColors.rose,
                                child: ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                                  itemCount: items.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                                  itemBuilder: (context, i) {
                                    final n = items[i];
                                    return AiraCard(
                                      padding: const EdgeInsets.all(14),
                                      borderColor: n.isRead ? AiraColors.hair : AiraColors.pinkBorder,
                                      onTap: () => _openDetail(n),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          SunndariIconBubble(icon: _iconFor(n), size: 44),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(n.title,
                                                    style: AiraText.sans(
                                                        fontSize: 14,
                                                        fontWeight: n.isRead ? FontWeight.w600 : FontWeight.w800,
                                                        color: AiraColors.roseDeep)),
                                                const SizedBox(height: 3),
                                                Text(n.message,
                                                    maxLines: 2,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: AiraText.sans(
                                                        fontSize: 12.5, color: AiraColors.charcoalSoft, height: 1.35)),
                                                const SizedBox(height: 6),
                                                Text(_timeAgo(n.createdAt),
                                                    style: AiraText.sans(fontSize: 11, color: AiraColors.charcoalSoft)),
                                              ],
                                            ),
                                          ),
                                          if (!n.isRead)
                                            Container(
                                              width: 9,
                                              height: 9,
                                              margin: const EdgeInsets.only(top: 4, left: 8),
                                              decoration: const BoxDecoration(
                                                  shape: BoxShape.circle, color: AiraColors.rose),
                                            ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
