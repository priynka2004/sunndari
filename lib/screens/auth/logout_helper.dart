// FILE: screens/auth/logout_helper.dart
// Shared "Log Out" flow used by onboarding screens (and anywhere a user may need to get out).
// Asks for confirmation, clears the session + push/notification state, then returns to Login
// with a clean back stack.

import 'package:flutter/material.dart';

import '../../api/help_center_notifier.dart';
import '../../services/push_notification_service.dart';
import '../../theme/tokens.dart';
import '../../utils/notification_badge.dart';
import '../../utils/service_locator.dart';
import 'delete_account_helper.dart';
import 'login_screen.dart';

/// Clears the session and goes to the Login screen (no confirmation).
Future<void> performLogout(BuildContext context) async {
  final navigator = Navigator.of(context);
  try {
    await PushNotificationService.instance.resetForLogout();
  } catch (_) {}
  try {
    await HelpCenterNotifier.instance.stop();
  } catch (_) {}
  try {
    await ServiceLocator.authService.logout();
  } catch (_) {}
  try {
    NotificationBadge.instance.clear();
  } catch (_) {}
  navigator.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (r) => false);
}

/// Shows a confirmation sheet, then logs out. Returns true if the user logged out.
/// The sheet also offers "Delete Account", so accounts that are still in onboarding can be removed too.
Future<bool> confirmAndLogout(BuildContext context) async {
  final choice = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Back To Sign In?', style: AiraText.serif(fontSize: 20, fontWeight: FontWeight.w700)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Already Have An Account? Log Out Here And Sign In With Your Mobile Number Or SUNNDARI Code.',
            style: AiraText.sans(fontSize: 13.5, color: AiraColors.charcoalSoft, height: 1.4),
          ),
          const SizedBox(height: 6),
          TextButton(
            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 32)),
            onPressed: () => Navigator.of(ctx).pop('delete'),
            child: Text('Delete My Account Instead',
                style: AiraText.sans(fontSize: 12.5, fontWeight: FontWeight.w600, color: AiraColors.errorText)),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop('stay'),
          child: Text('Stay Here',
              style: AiraText.sans(fontSize: 14, fontWeight: FontWeight.w600, color: AiraColors.charcoalSoft)),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop('logout'),
          child: Text('Log Out', style: AiraText.sans(fontSize: 14, fontWeight: FontWeight.w700, color: AiraColors.rose)),
        ),
      ],
    ),
  );
  if (!context.mounted) return false;
  if (choice == 'delete') {
    await confirmAndDeleteAccount(context);
    return false;
  }
  if (choice != 'logout') return false;
  await performLogout(context);
  return true;
}
