// FILE: services/service_announcement_service.dart  |  SERVICE
// "New service" popup: when the admin announces a seasonal service (Diwali Special, New Year Special …)
// every approved artist gets a notification (type `service_activated`) AND a popup in the app.
//
// APIs used:
//   GET  /core/service-sub-category/recently_activated/   (artist only, no parameters) → services announced in the
//                                                          last 15 days that THIS artist has not added yet
//   POST /artists/services/add/                           (idempotent) → adds the service to the artist's list
//   then the normal Add Service form opens (POST /artists/packages/create/) — a package is what makes the
//   service visible to customers.
//
// Rules from the backend guide:
//   • Remember `subCategoryId` + `announcedAt` on the device when an item is shown; show only items not shown yet.
//   • A re-announcement has a NEW announcedAt, so it shows again.
//   • Reading a notification does not change the popup, and the popup does not change notifications.
//   • An empty list means "show nothing" (also what a not-yet-approved artist gets).

import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_endpoints.dart';
import '../models/artist/add_service.dart';
import '../screens/packages_screen.dart' show AddServiceFromNotificationScreen;
import '../theme/tokens.dart';
import '../utils/app_feedback.dart';
import '../utils/app_session.dart';
import '../utils/service_locator.dart';
import '../widgets/common.dart';

/// One announced service (one item of the popup list).
class ServiceAnnouncement {
  final int subCategoryId;
  final String name;
  final String description;
  final String? categoryName;
  final String message; // the admin's wording, shown in the popup
  final String announcedAt; // ISO time — kept as text on purpose, it is only compared for equality

  const ServiceAnnouncement({
    required this.subCategoryId,
    required this.name,
    required this.description,
    required this.categoryName,
    required this.message,
    required this.announcedAt,
  });

  /// Builds one item from the API JSON; returns null when it has no usable id / name.
  static ServiceAnnouncement? tryParse(dynamic j) {
    if (j is! Map) return null;
    final idRaw = j['subCategoryId'] ?? j['sub_category_id'];
    final id = idRaw is num ? idRaw.toInt() : int.tryParse('${idRaw ?? ''}');
    final name = '${j['name'] ?? ''}'.trim();
    if (id == null || name.isEmpty) return null;
    final cat = j['category'];
    return ServiceAnnouncement(
      subCategoryId: id,
      name: name,
      description: '${j['description'] ?? ''}'.trim(),
      categoryName: cat is Map ? ('${cat['name'] ?? ''}'.trim().isEmpty ? null : '${cat['name']}'.trim()) : null,
      message: '${j['message'] ?? ''}'.trim(),
      announcedAt: '${j['announcedAt'] ?? j['announced_at'] ?? ''}',
    );
  }
}

/// Fetches the announcements, remembers which ones were already shown, and shows the popup.
class ServiceAnnouncementService {
  ServiceAnnouncementService._();
  static final ServiceAnnouncementService instance = ServiceAnnouncementService._();

  bool _busy = false;
  DateTime _lastCheck = DateTime.fromMillisecondsSinceEpoch(0);

  /// True when a check found something to show but another screen was on top — try again soon.
  bool hasDeferred = false;

  /// Per-user key, so two accounts on one phone do not share "already shown".
  static String get _shownKey => 'service_announce_shown_${AppSession.instance.userId ?? 0}';

  /// API: GET /core/service-sub-category/recently_activated/
  Future<List<ServiceAnnouncement>> fetch() async {
    final res = await ServiceLocator.apiService.get(ApiEndpoints.coreServiceSubCategoryRecentlyActivated);
    final body = jsonDecode(res.body);
    final data = body is Map ? body['data'] : null;
    if (data is! List) return const [];
    return data.map(ServiceAnnouncement.tryParse).whereType<ServiceAnnouncement>().toList();
  }

  /// subCategoryId (as text) → announcedAt that was already shown on this phone.
  Future<Map<String, String>> _loadShown() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_shownKey);
      if (raw == null || raw.isEmpty) return {};
      final m = jsonDecode(raw);
      if (m is! Map) return {};
      return m.map((k, v) => MapEntry('$k', '$v'));
    } catch (_) {
      return {};
    }
  }

  Future<void> _markShown(ServiceAnnouncement a) async {
    try {
      final shown = await _loadShown();
      shown['${a.subCategoryId}'] = a.announcedAt;
      await (await SharedPreferences.getInstance()).setString(_shownKey, jsonEncode(shown));
    } catch (_) {}
  }

  /// Checks for new announcements and shows the popup for each one not shown yet (at most 3 per check).
  /// Safe to call often: it ignores calls while a check is running and, unless [force], repeats at most every 15 s.
  /// Never throws — a failed check just shows nothing.
  Future<void> checkAndShow(BuildContext context, {bool force = false}) async {
    if (_busy) return;
    final now = DateTime.now();
    if (!force && now.difference(_lastCheck) < const Duration(seconds: 15)) return;
    _busy = true;
    _lastCheck = now;
    try {
      final list = await fetch();
      if (list.isEmpty) {
        hasDeferred = false;
        return;
      }
      final shown = await _loadShown();
      final pending = list.where((a) => shown['${a.subCategoryId}'] != a.announcedAt).take(3).toList();
      hasDeferred = false;
      for (final a in pending) {
        if (!context.mounted) return;
        // Only pop up over the main screen — if another screen/dialog is on top, try again later.
        final route = ModalRoute.of(context);
        if (route != null && !route.isCurrent) {
          hasDeferred = true;
          return;
        }
        await _markShown(a);
        if (!context.mounted) return;
        final wantsToAdd = await _showPopup(context, a);
        if (wantsToAdd == true) {
          if (!context.mounted) return;
          await _startAdd(context, a);
          break; // the artist is now in the add flow — do not stack another popup behind it
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[ServiceAnnouncement] check failed: $e');
    } finally {
      _busy = false;
    }
  }

  /// "Add This Service": POST /artists/services/add/ (idempotent), then the normal Add Service form
  /// opens with this service already chosen (POST /artists/packages/create/ happens when the artist saves).
  Future<void> _startAdd(BuildContext context, ServiceAnnouncement a) async {
    try {
      // API call: artistService.addService → POST /artists/services/add/
      await ServiceLocator.artistService.addService(AddService(subCategoryId: a.subCategoryId));
    } catch (e) {
      // e.g. 400 "This service is currently unavailable" (the admin switched it off) — say so and stop.
      if (context.mounted) AppFeedback.showWarning(context, e.toString().replaceFirst('Exception: ', ''));
      return;
    }
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddServiceFromNotificationScreen(subCategoryId: a.subCategoryId, serviceName: a.name),
      ),
    );
  }

  /// The popup. Returns true when the artist taps "Add This Service".
  Future<bool?> _showPopup(BuildContext context, ServiceAnnouncement a) {
    final headline = a.message.isNotEmpty ? a.message : '${a.name} is now available. Add it to your services to start getting bookings.';
    return showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AiraColors.bg,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SunndariIconBubble(icon: Icons.auto_awesome_outlined, size: 56),
                const SizedBox(height: 14),
                Text('New Service',
                    style: AiraText.sans(fontSize: 12.5, fontWeight: FontWeight.w700, color: AiraColors.rose)),
                const SizedBox(height: 4),
                Text(a.name, textAlign: TextAlign.center, style: AiraText.serif(fontSize: 24)),
                if ((a.categoryName ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(a.categoryName!,
                      style: AiraText.sans(fontSize: 12.5, fontWeight: FontWeight.w600, color: AiraColors.charcoalSoft)),
                ],
                const SizedBox(height: 14),
                Text(headline,
                    textAlign: TextAlign.center,
                    style: AiraText.sans(fontSize: 14.5, fontWeight: FontWeight.w500, color: AiraColors.charcoal)),
                if (a.description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(a.description,
                      textAlign: TextAlign.center,
                      style: AiraText.sans(fontSize: 13, fontWeight: FontWeight.w500, color: AiraColors.charcoalSoft)),
                ],
                const SizedBox(height: 20),
                PrimaryButton(
                  label: 'Add This Service',
                  icon: Icons.add_rounded,
                  expand: true,
                  onTap: () => Navigator.of(ctx).pop(true),
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text('Maybe Later',
                      style: AiraText.sans(fontSize: 14, fontWeight: FontWeight.w700, color: AiraColors.charcoalSoft)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
