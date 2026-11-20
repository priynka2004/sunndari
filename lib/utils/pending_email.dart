// FILE: utils/pending_email.dart
// The email typed on the sign-up screen. The server only saves an email after a code check
// (POST /users/contact/change/request/ + /verify/), so until then it is kept on the device and
// shown in Edit Profile with a "Verify" button — instead of the profile saying "Not Added".

import 'package:shared_preferences/shared_preferences.dart';
import 'app_session.dart';

class PendingEmail {
  static String get _key => 'pending_email_${AppSession.instance.userId ?? 0}';

  static Future<String> load() async {
    try {
      return (await SharedPreferences.getInstance()).getString(_key) ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<void> save(String email) async {
    try {
      await (await SharedPreferences.getInstance()).setString(_key, email.trim());
    } catch (_) {}
  }

  static Future<void> clear() async {
    try {
      await (await SharedPreferences.getInstance()).remove(_key);
    } catch (_) {}
  }
}
