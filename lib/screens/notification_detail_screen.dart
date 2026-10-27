// FILE: screens/notification_detail_screen.dart
// SCREEN: Notification Detail — opened from the list or from a push-notification tap.
//
// APIs used:
//   GET /notifications/get/
//   PUT /notifications/mark_read/

import 'package:flutter/material.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../models/notification/app_notification.dart';
import '../utils/app_session.dart';
import '../utils/service_locator.dart';
import 'chat_screen.dart';
import 'booking_detail_screen.dart';
import 'business_details_screen.dart';
import 'changes_required_screen.dart';
import 'help_center_screen.dart';
import 'packages_screen.dart' show AddServiceFromNotificationScreen;
import '../utils/app_feedback.dart';

/// SCREEN: Notification Detail — opened from the list or from a push-notification tap.
class NotificationDetailScreen extends StatefulWidget {
  final int notificationId;
  final AppNotification? notification;

  const NotificationDetailScreen({
    super.key,
    required this.notificationId,
    this.notification,
  });

  @override
  State<NotificationDetailScreen> createState() => _NotificationDetailScreenState();
}

/// State of [NotificationDetailScreen] — holds the screen data and logic.
class _NotificationDetailScreenState extends State<NotificationDetailScreen> {
  bool _loading = true;
  String? _error;
  AppNotification? _item;

  /// Runs once when the screen opens; starts: _load().
  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Loads this screen's data.
  /// API: notificationService.getNotification → GET /notifications/get/
  Future<void> _load() async {
    if (widget.notification != null) {
      _item = widget.notification;
      _loading = false;
      _markReadIfNeeded();
      if (mounted) setState(() {});
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // API call: notificationService.getNotification → GET /notifications/get/
      final n = await ServiceLocator.notificationService.getNotification(widget.notificationId);
      if (!mounted) return;
      setState(() {
        _item = n;
        _loading = false;
      });
      _markReadIfNeeded();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  /// Marks read if needed.
  /// Uses 2 APIs (see inline notes).
  Future<void> _markReadIfNeeded() async {
    final n = _item;
    if (n == null || n.isRead) return;
    try {
      if (n.firestoreDocId != null) {
        final userId = AppSession.instance.userId;
        if (userId != null) {
          // API call: firestoreNotificationService.markAsRead
          await ServiceLocator.firestoreNotificationService.markAsRead(userId, n.firestoreDocId!);
        }
      } else {
        // API call: notificationService.markRead → PUT /notifications/mark_read/
        await ServiceLocator.notificationService.markRead(n.notificationId);
      }
      if (mounted) setState(() => _item = n.copyWith(isRead: true));
    } catch (_) {
    }
  }

  /// Formats date.
  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final suffix = dt.hour >= 12 ? 'PM' : 'AM';
    final min = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}, $h:$min $suffix';
  }

  /// Returns true if page feedback.
  bool get _isPageFeedback {
    final t = '${_item?.type ?? ''} ${_item?.title ?? ''}'.toLowerCase();
    return t.contains('changes') || t.contains('needs attention') || t.contains('need attention') || t.contains('page_review');
  }

  /// Opens changes.
  void _openChanges() {
    final nav = Navigator.of(context);
    nav.push(MaterialPageRoute(
      builder: (ctx) => ChangesRequiredScreen(
        changes: [
          ReviewChange(
            title: 'Service Details',
            body: _item!.message.trim().isNotEmpty ? _item!.message.trim() : 'Clarify What Your Packages Include.',
            icon: Icons.description_outlined,
            actionLabel: 'Edit Service',
            onAction: () => nav.push(MaterialPageRoute(builder: (_) => const BusinessDetailsScreen(initialTab: 'package'))),
          ),
          ReviewChange(
            title: 'Portfolio Image',
            body: 'Replace Any Blurred Image With A Clear Photo Of Your Work.',
            icon: Icons.image_outlined,
            actionLabel: 'Update Portfolio',
            onAction: () => nav.push(MaterialPageRoute(builder: (_) => const BusinessDetailsScreen(initialTab: 'portfolio'))),
          ),
        ],
        onResubmit: () {
          Navigator.of(ctx).pop();
          AppFeedback.showSuccess(context, 'Resubmitted For Review ✓');
        },
        onContactSupport: () => Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => const HelpCenterScreen())),
      ),
    ));
  }

  /// Returns true if chat.
  bool get _isChat => (_item?.type.toLowerCase().contains('chat') ?? false) && _item?.bookingId != null;

  /// Returns true if booking.
  bool get _isBooking => !_isChat && _item?.bookingId != null;

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
                  Expanded(
                    child: Text('Notification', style: AiraText.serif(fontSize: 19, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4, color: AiraColors.rose))
                  : _error != null
                      ? AiraErrorState(message: _error!, onRetry: _load)
                      : _item == null
                          ? const SizedBox.shrink()
                          : SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                              child: AiraCard(
                                padding: const EdgeInsets.all(18),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AiraColors.blush,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        _item!.type.toUpperCase(),
                                        style: AiraText.sans(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w600,
                                          color: AiraColors.roseDeep,
                                          letterSpacing: 0.4,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    Text(_item!.title, style: AiraText.serif(fontSize: 20, fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 10),
                                    Text(_item!.message,
                                        style: AiraText.sans(fontSize: 14, color: AiraColors.charcoalSoft, height: 1.5)),
                                    const SizedBox(height: 16),
                                    Text(_formatDate(_item!.createdAt),
                                        style: AiraText.sans(fontSize: 11.5, color: AiraColors.charcoalSoft)),
                                    if (_isChat) ...[
                                      const SizedBox(height: 20),
                                      PrimaryButton(
                                        label: 'Open Chat',
                                        icon: Icons.chat_bubble_outline,
                                        expand: true,
                                        // Navigates to ChatScreen
                                        onTap: () => Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => ChatScreen(
                                              bookingId: _item!.bookingId!,
                                              title: _item!.title.trim().isNotEmpty ? _item!.title.trim() : 'Chat',
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                    if (_item!.isAddServicePrompt) ...[
                                      const SizedBox(height: 20),
                                      PrimaryButton(
                                        label: 'Add This Service',
                                        icon: Icons.add_rounded,
                                        expand: true,
                                        onTap: () => Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => AddServiceFromNotificationScreen(subCategoryId: _item!.subCategoryId),
                                          ),
                                        ),
                                      ),
                                    ],
                                    if (_isPageFeedback) ...[
                                      const SizedBox(height: 20),
                                      PrimaryButton(
                                        label: 'Review Changes',
                                        icon: Icons.rule_rounded,
                                        expand: true,
                                        onTap: _openChanges,
                                      ),
                                    ],
                                    if (_isBooking) ...[
                                      const SizedBox(height: 20),
                                      PrimaryButton(
                                        label: 'View Booking',
                                        icon: Icons.calendar_today_outlined,
                                        expand: true,
                                        // Navigates to BookingDetailScreen
                                        onTap: () => Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => BookingDetailScreen(bookingId: _item!.bookingId!),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }
}
