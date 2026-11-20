// FILE: utils/fcm_token_helper.dart
// Reads this phone's current Firebase push token so it can be sent with every sign-in call
// (phone OTP, email OTP, password, Google and token refresh). The server saves it for the user.

import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';

/// Helper: current FCM (push) token of this device.
class FcmTokenHelper {
  FcmTokenHelper._();

  /// The device's current Firebase token, or null when it is not available
  /// (no permission, Firebase not ready, offline). A missing token never blocks sign-in:
  /// the server simply keeps the one it already has.
  static Future<String?> current() async {
    try {
      final token = await FirebaseMessaging.instance.getToken().timeout(const Duration(seconds: 4));
      if (token == null || token.trim().isEmpty) return null;
      return token;
    } catch (_) {
      return null;
    }
  }

  /// Adds `fcm_token` to a sign-in request body when a token is available.
  static Future<Map<String, dynamic>> withToken(Map<String, dynamic> body) async {
    final token = await current();
    if (token != null) body['fcm_token'] = token;
    return body;
  }
}
