// FILE: services/push_notification_service.dart
// Firebase Cloud Messaging (push) + local notifications: permission, FCM token save, foreground/background/tap handling.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../firebase_options.dart';
import '../screens/chat_screen.dart';
import '../screens/booking_detail_screen.dart';
import '../screens/notification_detail_screen.dart';
import '../screens/help_center_screen.dart';
import '../screens/packages_screen.dart' show AddServiceFromNotificationScreen;
import '../models/notification/app_notification.dart' show isAddServiceNotificationType;
import '../utils/app_session.dart';
import '../utils/nav_key.dart';
import '../utils/notification_badge.dart';
import '../utils/service_locator.dart';

/// Firebase messaging background handler.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (e) {
    if (kDebugMode) debugPrint('[Push] Firebase.initializeApp in background isolate: $e');
  }

  if (kDebugMode) {
    debugPrint('[Push] background message: ${message.messageId} | ${message.data}');
  }

  if (!Platform.isAndroid) {
    return;
  }

  try {
    final localNotifications = FlutterLocalNotificationsPlugin();
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await localNotifications.initialize(const InitializationSettings(android: androidInit));

    const channel = AndroidNotificationChannel(
      'aira_notifications',
      'Sunndari Notifications',
      description: 'Booking, Chat And Account Updates From Sunndari',
      importance: Importance.max,
    );
    await localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
    final title = message.notification?.title ??
        message.data['title']?.toString() ??
        'Sunndari';
    final body = message.notification?.body ??
        message.data['message']?.toString() ??
        message.data['body']?.toString() ??
        '';

    await localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: Importance.max,
          priority: Priority.high,
          visibility: NotificationVisibility.public,
        ),
      ),
      payload: jsonEncode(message.data),
    );
  } catch (e) {
    if (kDebugMode) debugPrint('[Push] failed to draw background notification: $e');
  }
}

/// Push Notification Service — API/data layer.
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  static const _androidChannel = AndroidNotificationChannel(
    'aira_notifications',
    'Sunndari Notifications',
    description: 'Booking, Chat And Account Updates From Sunndari',
    importance: Importance.max,
  );

  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _localNotificationsInitialized = false;
  bool _messagingInitialized = false;
  String? _subscribedTopic;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _badgeSub;

  /// Initialises local notifications.
  Future<void> initLocalNotifications() async {
    if (_localNotificationsInitialized) return;
    _localNotificationsInitialized = true;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _localNotifications.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (response) {
        _handleTapPayload(response.payload);
      },
    );

    final androidImpl = _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(_androidChannel);
    await androidImpl?.requestNotificationsPermission();
  }

  /// Initialises messaging.
  Future<void> initMessaging() async {
    if (_messagingInitialized) return;
    _messagingInitialized = true;

    final messaging = FirebaseMessaging.instance;

    await messaging.requestPermission(alert: true, badge: true, sound: true);

    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    await _subscribeToOwnTopic();
    await _saveToken();
    await _printTokenForTesting();
    _listenForFirestoreBadge();
    messaging.onTokenRefresh.listen((token) => _saveToken(token));

    FirebaseMessaging.onMessage.listen(_onForegroundMessage);

    FirebaseMessaging.onMessageOpenedApp.listen((message) => _navigateFor(message.data));

    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _navigateFor(initialMessage.data));
    }
  }

  /// Saves token.
  Future<void> _saveToken([String? token]) async {
    final fcmToken = token ?? await FirebaseMessaging.instance.getToken();
    if (fcmToken == null) return;
    await Future.wait([
      _saveTokenToFirestore(fcmToken),
      _saveTokenToBackend(fcmToken),
    ]);
  }

  /// Saves token to firestore.
  Future<void> _saveTokenToFirestore([String? token]) async {
    final userId = AppSession.instance.userId;
    if (userId == null) return;
    try {
      final fcmToken = token ?? await FirebaseMessaging.instance.getToken();
      if (fcmToken == null) return;
      await _firestore.collection('fcm_tokens').doc(userId.toString()).set({
        'userId': userId,
        'fcmToken': fcmToken,
        'platform': Platform.isIOS ? 'ios' : 'android',
        'isActive': true,
      }, SetOptions(merge: true));
      if (kDebugMode) debugPrint('[Push] token saved to fcm_tokens/$userId');
    } catch (e) {
      if (kDebugMode) debugPrint('[Push] failed to save token to Firestore: $e');
    }
  }

  /// Saves token to backend.
  /// API: userService.updateFcmToken
  Future<void> _saveTokenToBackend(String fcmToken) async {
    if (AppSession.instance.userId == null) return;
    try {
      await ServiceLocator.userService.updateFcmToken(fcmToken);
      if (kDebugMode) debugPrint('[Push] token sent to backend via profile update');
    } catch (e) {
      if (kDebugMode) debugPrint('[Push] failed to send token via profile update: $e');
    }
  }

  /// Prints token for testing — switched off (commented out) so the FCM token no longer shows in the log.
  Future<void> _printTokenForTesting() async {
    // if (!kDebugMode) return;
    // try {
    //   final token = await FirebaseMessaging.instance.getToken();
    //   debugPrint('=================== FCM TOKEN ===================');
    //   debugPrint(token);
    //   debugPrint('==================================================');
    // } catch (e) {
    //   debugPrint('[Push] failed to fetch FCM token for testing: $e');
    // }
  }

  /// Subscribes to to own topic.
  Future<void> _subscribeToOwnTopic() async {
    final userId = AppSession.instance.userId;
    if (userId == null) return;
    final topic = 'user_$userId';
    try {
      await FirebaseMessaging.instance.subscribeToTopic(topic);
      _subscribedTopic = topic;
      if (kDebugMode) debugPrint('[Push] subscribed to topic: $topic');
    } catch (e) {
      if (kDebugMode) debugPrint('[Push] failed to subscribe to topic $topic: $e');
    }
  }

  /// Listens to for firestore badge.
  void _listenForFirestoreBadge() {
    final userId = AppSession.instance.userId;
    if (userId == null) return;
    _badgeSub?.cancel();
    _badgeSub = _firestore
        .collection('user')
        .doc(userId.toString())
        .collection('notifications')
        .where('isRead', isEqualTo: false)
        .snapshots()
        .listen(
          (snapshot) {
        if (snapshot.docs.isNotEmpty) NotificationBadge.instance.markUnread();
      },
      onError: (e) {
        if (kDebugMode) debugPrint('[Push] Firestore badge listener error: $e');
      },
    );
  }

  /// Resets for logout.
  Future<void> resetForLogout() async {
    await _badgeSub?.cancel();
    _badgeSub = null;

    final userId = AppSession.instance.userId;
    if (userId != null) {
      try {
        await _firestore
            .collection('fcm_tokens')
            .doc(userId.toString())
            .set({'isActive': false}, SetOptions(merge: true));
      } catch (e) {
        if (kDebugMode) debugPrint('[Push] failed to deactivate token doc: $e');
      }
    }

    final topic = _subscribedTopic;
    if (topic != null) {
      try {
        await FirebaseMessaging.instance.unsubscribeFromTopic(topic);
      } catch (e) {
        if (kDebugMode) debugPrint('[Push] failed to unsubscribe from $topic: $e');
      }
      _subscribedTopic = null;
    }
    _messagingInitialized = false;
  }

  /// Callback when foreground message happens.
  Future<void> _onForegroundMessage(RemoteMessage message) async {
    if (kDebugMode) {
      debugPrint('[Push] foreground message: ${message.messageId} | data=${message.data} | notification.title=${message.notification?.title} | notification.body=${message.notification?.body}');
    }

    NotificationBadge.instance.markUnread();

    final notification = message.notification;
    final title = notification?.title ?? message.data['title'] as String? ?? 'Sunndari';
    final body = notification?.body ?? message.data['message'] as String? ?? '';

    if (!Platform.isAndroid) {
      return;
    }

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannel.id,
          _androidChannel.name,
          channelDescription: _androidChannel.description,
          importance: Importance.max,
          priority: Priority.high,
          visibility: NotificationVisibility.public,
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }

  /// Handles tap payload.
  void _handleTapPayload(String? payload) {
    if (payload == null || payload.isEmpty) return;
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      _navigateFor(data.map((k, v) => MapEntry(k, v?.toString())));
    } catch (e) {
      if (kDebugMode) debugPrint('[Push] bad tap payload: $payload ($e)');
    }
  }

  /// Shows help center reply.
  Future<void> showHelpCenterReply(String body) async {
    await initLocalNotifications();
    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'Support Replied',
      body.isEmpty ? 'You Have A New Message From Support.' : body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannel.id,
          _androidChannel.name,
          channelDescription: _androidChannel.description,
          importance: Importance.max,
          priority: Priority.high,
          visibility: NotificationVisibility.public,
        ),
      ),
      payload: jsonEncode({'type': 'help_center'}),
    );
  }

  /// Navigates to for.
  void _navigateFor(Map<String, dynamic> data) {
    final nav = navigatorKey.currentState;
    if (nav == null) return;

    if (kDebugMode) debugPrint('[Push] tap payload: $data');

    final type = (data['type'] ?? data['notification_type'] ?? data['notificationType'] ?? '')
        .toString()
        .toLowerCase();
    final bookingId = int.tryParse(
        '${data['booking_id'] ?? data['bookingId'] ?? data['booking'] ?? ''}');
    final notificationId = int.tryParse(
        '${data['notification_id'] ?? data['notificationId'] ?? data['id'] ?? ''}');

    if (type.contains('help')) {
      nav.push(MaterialPageRoute(builder: (_) => const HelpCenterScreen()));
      return;
    }

    // Admin's "add this special service" notification → straight to the Add Service screen.
    // (Only this type; every other notification below keeps its old navigation.)
    if (isAddServiceNotificationType(type)) {
      nav.push(MaterialPageRoute(
        builder: (_) => AddServiceFromNotificationScreen(
          subCategoryId: int.tryParse(
              '${data['referenceId'] ?? data['reference_id'] ?? data['sub_category_id'] ?? data['subCategoryId'] ?? ''}'),
          serviceName: (data['service_name'] ?? data['serviceName'])?.toString(),
        ),
      ));
      return;
    }

    final looksLikeChat =
        type.contains('chat') || type.contains('message');
    final looksLikeBooking = type.contains('book');

    if (looksLikeChat && bookingId != null) {
      final senderName = (data['sender_name'] ??
          data['senderName'] ??
          data['customer_name'] ??
          data['customerName'] ??
          data['artist_name'] ??
          data['artistName'])
          ?.toString();
      nav.push(MaterialPageRoute(
        builder: (_) => ChatScreen(
          bookingId: bookingId,
          title: (senderName != null && senderName.trim().isNotEmpty) ? senderName.trim() : 'Chat',
        ),
      ));
      return;
    }

    if (looksLikeBooking && bookingId != null) {
      nav.push(MaterialPageRoute(builder: (_) => BookingDetailScreen(bookingId: bookingId)));
      return;
    }

    if (notificationId != null) {
      nav.push(MaterialPageRoute(builder: (_) => NotificationDetailScreen(notificationId: notificationId)));
      return;
    }

    if (bookingId != null) {
      nav.push(MaterialPageRoute(builder: (_) => BookingDetailScreen(bookingId: bookingId)));
    }
  }
}
